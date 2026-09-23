#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: build-ipa.sh YouTube.ipa [output.ipa]" >&2
  exit 2
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${2:-$PWD/YTLitePlusRenewed.ipa}")"
LOADER="$HERE/.theos/obj/YTLPRLoader.dylib"
BUNDLE="$HERE/YTLPR.bundle"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$INPUT" ]] || { echo "can't find $INPUT" >&2; exit 1; }
[[ -f "$LOADER" ]] || { echo "build the loader first: run make in $HERE" >&2; exit 1; }

python3 - "$BUNDLE" <<'PY'
import json, os, sys
bundle = sys.argv[1]
try:
    config = json.load(open(os.path.join(bundle, "Tweaks.json")))
except ValueError as error:
    sys.exit(f"Tweaks.json has a typo: {error}")
listed = set()
for section in config.get("sections", []):
    for tweak in section.get("tweaks", []):
        listed.add(tweak["file"])
on_disk = {name for name in os.listdir(bundle) if name.endswith(".dylib")}
for name in sorted(listed - on_disk):
    print(f"warning: {name} is in Tweaks.json but not in YTLPR.bundle")
for name in sorted(on_disk - listed):
    print(f"warning: {name} is in YTLPR.bundle but not in Tweaks.json, so it will never load")
PY

unzip -q "$INPUT" -d "$WORK"
APP="$(find "$WORK/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP" ]] || { echo "no .app inside $INPUT" >&2; exit 1; }
MAIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

OLD=()
while IFS= read -r load; do
  case "$load" in
    *widevine*|*CydiaSubstrate.framework*) ;;
    @rpath/*.dylib|@executable_path/*.dylib) OLD+=("$load") ;;
  esac
done < <(python3 "$HERE/Tools/macho_inject.py" "$MAIN" --list | grep -E '^@')

ARGS=()
for load in ${OLD[@]+"${OLD[@]}"}; do
  ARGS+=(--remove-load "$load")
  file="$APP/Frameworks/$(basename "$load")"
  [[ -f "$file" ]] && rm -f "$file"
  echo "removed old injected $(basename "$load")"
done
rm -f "$APP/Frameworks/TweakLoader.dylib"
python3 "$HERE/Tools/macho_inject.py" "$MAIN" ${ARGS[@]+"${ARGS[@]}"} --add-load '@rpath/YTLPRLoader.dylib'

mkdir -p "$APP/Frameworks"
cp "$LOADER" "$APP/Frameworks/YTLPRLoader.dylib"
if [[ -d "$HERE/Frameworks" ]]; then
  cp -R "$HERE/Frameworks/." "$APP/Frameworks/"
fi
[[ -e "$APP/Frameworks/CydiaSubstrate.framework" ]] || echo "warning: no CydiaSubstrate.framework, tweaks won't load"
if [[ -d "$HERE/Resources" ]]; then
  for item in "$HERE/Resources/"*; do
    [[ -e "$item" ]] || continue
    rm -rf "$APP/$(basename "$item")"
    cp -R "$item" "$APP/"
  done
fi
rm -rf "$APP/YTLPR.bundle"
cp -R "$BUNDLE" "$APP/YTLPR.bundle"
for dylib in "$APP/YTLPR.bundle/"*.dylib; do
  for old in /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate /usr/lib/libsubstrate.dylib; do
    if otool -L "$dylib" | grep -q "^[[:space:]]*$old "; then
      install_name_tool -change "$old" @rpath/CydiaSubstrate.framework/CydiaSubstrate "$dylib" 2>/dev/null
      echo "fixed Substrate path in $(basename "$dylib")"
    fi
  done
done
rm -rf "$APP/_CodeSignature"

if command -v ldid >/dev/null 2>&1; then
  ENTITLEMENTS="$WORK/entitlements.plist"
  ldid -e "$MAIN" > "$ENTITLEMENTS" 2>/dev/null || true
  while IFS= read -r binary; do
    [[ "$binary" == "$MAIN" ]] || ldid -S "$binary"
  done < <(python3 "$HERE/Tools/list_macho.py" "$APP")
  if [[ -s "$ENTITLEMENTS" ]]; then ldid "-S$ENTITLEMENTS" "$MAIN"; else ldid -S "$MAIN"; fi
fi

(cd "$WORK" && zip -qry "$WORK/out.ipa" Payload)
mkdir -p "$(dirname "$OUTPUT")"
mv -f "$WORK/out.ipa" "$OUTPUT"
echo "$OUTPUT"
