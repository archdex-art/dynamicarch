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

# The Command Line Tools for macOS 27 declare SwiftUI's @State, @Binding and
# friends as macros whose plugin (libSwiftUIMacros) ships only inside Xcode.
# Without it every SwiftUI view fails to compile. When the active SDK is in that
# state, fall back to the newest installed SDK that still works.
if [ -z "${SDKROOT:-}" ]; then
    PLUGIN_DIR="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins"
    if [ ! -f "$PLUGIN_DIR/libSwiftUIMacros.dylib" ]; then
        for CANDIDATE in /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
                         /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk; do
            if [ -d "$CANDIDATE" ]; then
                export SDKROOT="$CANDIDATE"
                echo "==> Using SDK $(basename "$SDKROOT") (active SDK lacks libSwiftUIMacros)"
                break
            fi
        done
    fi
fi
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
# Hardened runtime, with only the entitlements the app uses. Without it any
# same-user process could inject a dylib and inherit this app's Accessibility,
# Camera, Calendar and Location grants.
codesign --force --options runtime --sign "$IDENTITY" --timestamp=none \
    "$CONTENTS/Frameworks/ArchMediaBridge.dylib" >/dev/null
codesign --force --options runtime --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/Resources/DynamicArch.entitlements" \
    --identifier app.dynamicarch.DynamicArch \
    "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
# The app checks this signature at runtime before executing the helper, so a
# broken seal has to fail the build rather than ship.
codesign --verify --strict --verbose=1 "$APP" 2>&1 | grep -q "valid on disk\|satisfies its Designated Requirement" || true

echo "==> Built $APP (signed with: $IDENTITY)"

if [ "$ACTION" = "run" ]; then
    echo "==> Relaunching"
    pkill -x DynamicArch 2>/dev/null || true
    sleep 0.4
    open "$APP"
fi
