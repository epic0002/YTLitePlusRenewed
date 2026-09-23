#!/usr/bin/env python3

import pathlib
import struct
import sys

MAGICS = {
    0xFEEDFACE,
    0xFEEDFACF,
    0xCEFAEDFE,
    0xCFFAEDFE,
    0xCAFEBABE,
    0xBEBAFECA,
    0xCAFEBABF,
    0xBFBAFECA,
}


def is_macho(path: pathlib.Path) -> bool:
    try:
        with path.open("rb") as handle:
            prefix = handle.read(4)
    except OSError:
        return False
    if len(prefix) != 4:
        return False
    return (
        struct.unpack("<I", prefix)[0] in MAGICS
        or struct.unpack(">I", prefix)[0] in MAGICS
    )


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    files = [path for path in root.rglob("*") if path.is_file() and is_macho(path)]
    files.sort(key=lambda path: (len(path.parts), len(str(path))), reverse=True)
    for path in files:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
