#!/usr/bin/env python3

import argparse
import os
import pathlib
import struct
import sys
import tempfile
from dataclasses import dataclass

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
DYLIB_COMMANDS = {
    LC_LOAD_DYLIB,
    0x18 | 0x80000000,
    0x1F | 0x80000000,
    0x20,
    0x23 | 0x80000000,
}


class MachOError(RuntimeError):
    pass


@dataclass(frozen=True)
class Slice:
    offset: int
    size: int


@dataclass(frozen=True)
class Command:
    offset: int
    command: int
    size: int


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def slices(data: bytes) -> list[Slice]:
    if len(data) < 8:
        raise MachOError("file is too small")

    little_magic = struct.unpack_from("<I", data, 0)[0]
    if little_magic == MH_MAGIC_64:
        return [Slice(0, len(data))]

    big_magic = struct.unpack_from(">I", data, 0)[0]
    if big_magic not in {FAT_MAGIC, FAT_MAGIC_64}:
        raise MachOError("unsupported Mach-O format")

    count = struct.unpack_from(">I", data, 4)[0]
    entry_size = 32 if big_magic == FAT_MAGIC_64 else 20
    header_size = 8 + count * entry_size
    if header_size > len(data):
        raise MachOError("invalid fat header")

    result: list[Slice] = []
    for index in range(count):
        position = 8 + index * entry_size
        if big_magic == FAT_MAGIC_64:
            _, _, offset, size, _, _ = struct.unpack_from(">iiQQII", data, position)
        else:
            _, _, offset, size, _ = struct.unpack_from(">iiIII", data, position)
        if offset + size > len(data):
            raise MachOError("fat slice exceeds file")
        result.append(Slice(offset, size))
    return result


def header(data: bytes, item: Slice) -> tuple[int, int]:
    if item.size < 32:
        raise MachOError("slice is too small")
    magic, _, _, _, count, size, _, _ = struct.unpack_from(
        "<IiiIIIII", data, item.offset
    )
    if magic != MH_MAGIC_64:
        raise MachOError("only 64-bit little-endian slices are supported")
    if 32 + size > item.size:
        raise MachOError("load commands exceed slice")
    return count, size


def commands(data: bytes, item: Slice) -> list[Command]:
    count, total_size = header(data, item)
    position = item.offset + 32
    limit = position + total_size
    result: list[Command] = []

    for _ in range(count):
        if position + 8 > limit:
            raise MachOError("truncated load command")
        command, size = struct.unpack_from("<II", data, position)
        if size < 8 or position + size > limit:
            raise MachOError("invalid load command size")
        result.append(Command(position, command, size))
        position += size

    if position != limit:
        raise MachOError("load command size mismatch")
    return result


def dylib_name(data: bytes, item: Command) -> str | None:
    if item.command not in DYLIB_COMMANDS or item.size < 24:
        return None
    name_offset = struct.unpack_from("<I", data, item.offset + 8)[0]
    if name_offset >= item.size:
        raise MachOError("invalid dylib name offset")
    start = item.offset + name_offset
    end_limit = item.offset + item.size
    end = data.find(b"\0", start, end_limit)
    if end < 0:
        end = end_limit
    return data[start:end].decode("utf-8", errors="strict")


def first_payload_offset(data: bytes, item: Slice, items: list[Command]) -> int:
    candidates: list[int] = []
    for command in items:
        if command.command != LC_SEGMENT_64 or command.size < 72:
            continue
        section_count = struct.unpack_from("<I", data, command.offset + 64)[0]
        required = 72 + section_count * 80
        if required > command.size:
            raise MachOError("invalid segment sections")
        for index in range(section_count):
            section = command.offset + 72 + index * 80
            offset = struct.unpack_from("<I", data, section + 48)[0]
            if offset:
                candidates.append(offset)
    if not candidates:
        return item.size
    return min(candidates)


def matches(name: str, target: str) -> bool:
    return (
        name == target
        or name.endswith("/" + target)
        or pathlib.PurePosixPath(name).name == pathlib.PurePosixPath(target).name
    )


def make_dylib_command(name: str) -> bytes:
    encoded = name.encode("utf-8") + b"\0"
    size = align(24 + len(encoded), 8)
    result = bytearray(size)
    struct.pack_into("<IIIIII", result, 0, LC_LOAD_DYLIB, size, 24, 0, 0, 0)
    result[24 : 24 + len(encoded)] = encoded
    return bytes(result)


def rewrite_slice(
    data: bytearray,
    item: Slice,
    add_load: str | None,
    remove_loads: list[str],
) -> bool:
    original = bytes(data)
    items = commands(original, item)
    kept: list[bytes] = []
    existing: list[str] = []
    changed = False

    for command in items:
        name = dylib_name(original, command)
        if name is not None:
            if any(matches(name, target) for target in remove_loads):
                changed = True
                continue
            existing.append(name)
        kept.append(original[command.offset : command.offset + command.size])

    if add_load is not None and add_load not in existing:
        kept.append(make_dylib_command(add_load))
        changed = True

    if not changed:
        return False

    payload_offset = first_payload_offset(original, item, items)
    joined = b"".join(kept)
    command_start = item.offset + 32
    command_end = command_start + len(joined)
    slack_end = item.offset + payload_offset
    if command_end > slack_end:
        raise MachOError(
            f"insufficient header slack: need {command_end - slack_end} more bytes"
        )

    _, old_size = header(original, item)
    old_end = command_start + old_size
    data[command_start:command_end] = joined
    clear_end = max(old_end, command_end)
    if command_end < clear_end:
        data[command_end:clear_end] = b"\0" * (clear_end - command_end)

    struct.pack_into("<I", data, item.offset + 16, len(kept))
    struct.pack_into("<I", data, item.offset + 20, len(joined))
    return True


def rewrite(
    data: bytes,
    add_load: str | None = None,
    remove_loads: list[str] | None = None,
) -> bytes:
    result = bytearray(data)
    removals = remove_loads or []
    for item in slices(data):
        rewrite_slice(result, item, add_load, removals)
    return bytes(result)


def list_dylibs(data: bytes) -> list[list[str]]:
    result: list[list[str]] = []
    for item in slices(data):
        names = []
        for command in commands(data, item):
            name = dylib_name(data, command)
            if name is not None:
                names.append(name)
        result.append(names)
    return result


def atomic_write(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=path.name + ".", dir=str(path.parent)
    )
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=pathlib.Path)
    parser.add_argument("--add-load")
    parser.add_argument("--remove-load", action="append", default=[])
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--list", action="store_true")
    arguments = parser.parse_args(argv)

    try:
        source = arguments.binary.read_bytes()
        if arguments.list:
            for index, names in enumerate(list_dylibs(source)):
                print(f"slice {index}")
                for name in names:
                    print(name)
            return 0

        if arguments.add_load is None and not arguments.remove_load:
            parser.error("no rewrite requested")

        destination = arguments.output or arguments.binary
        atomic_write(
            destination,
            rewrite(source, arguments.add_load, arguments.remove_load),
        )
        return 0
    except (OSError, MachOError, UnicodeError) as error:
        print(f"macho_inject: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
