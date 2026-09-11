#!/bin/bash
# Builds DynamicArch.app without Xcode: SwiftPM for the app binary, clang for
# the MediaRemote bridge, then a hand-assembled, code-signed bundle.
#
#   ./Scripts/build.sh              release build + bundle
#   ./Scripts/build.sh debug        debug build + bundle
#   ./Scripts/build.sh release run  build, bundle, relaunch the app
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-release}"
ACTION="${2:-}"
APP="$ROOT/build/DynamicArch.app"
CONTENTS="$APP/Contents"

echo "==> Building Swift executable ($CONFIG)"
swift build -c "$CONFIG" --product DynamicArch
BINARY="$(swift build -c "$CONFIG" --product DynamicArch --show-bin-path)/DynamicArch"

echo "==> Building MediaRemote bridge"
mkdir -p "$ROOT/build/helpers"
clang -fobjc-arc -dynamiclib -O2 \
    -mmacosx-version-min=15.0 \
    -framework Foundation -framework AppKit \
    -o "$ROOT/build/helpers/ArchMediaBridge.dylib" \
    "$ROOT/Helper/ArchMediaBridge/bridge.m"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BINARY" "$CONTENTS/MacOS/DynamicArch"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
# The loader script is a sealed resource (scripts cannot carry a signature);
# the bridge is Mach-O and gets signed in its own right under Frameworks.
cp "$ROOT/Helper/archmedia.pl" "$CONTENTS/Resources/archmedia.pl"
cp "$ROOT/build/helpers/ArchMediaBridge.dylib" "$CONTENTS/Frameworks/ArchMediaBridge.dylib"
chmod +x "$CONTENTS/Resources/archmedia.pl"

if [ ! -f "$ROOT/build/AppIcon.icns" ]; then
    echo "==> Rendering app icon"
    swift "$ROOT/Scripts/make-icon.swift" "$ROOT/build/AppIcon.iconset" >/dev/null
    iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

echo "==> Signing"
# A stable signing identity keeps TCC grants (camera, calendar, location)
# across rebuilds. Scripts/make-signing-identity.sh creates one; without it we
# fall back to ad-hoc, which re-prompts for permissions on every build.
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "DynamicArch Developer"; then
    IDENTITY="DynamicArch Developer"
fi
codesign --force --sign "$IDENTITY" --timestamp=none \
    "$CONTENTS/Frameworks/ArchMediaBridge.dylib" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp=none \
    --identifier app.dynamicarch.DynamicArch \
    "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "==> Built $APP (signed with: $IDENTITY)"

if [ "$ACTION" = "run" ]; then
    echo "==> Relaunching"
    pkill -x DynamicArch 2>/dev/null || true
    sleep 0.4
    open "$APP"
fi
