#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/swift-cache"
build_options=(--cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --disable-sandbox)
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64 "${build_options[@]}"
    binary_path="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path "${build_options[@]}")"
else
    swift build -c release "${build_options[@]}"
    binary_path="$(swift build -c release --show-bin-path "${build_options[@]}")"
fi
app="$PWD/dist/Prisme.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_path/Prisme" "$app/Contents/MacOS/Prisme"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift -module-cache-path "$PWD/.build/icon-module-cache" scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
ditto -c -k --keepParent "$app" "$PWD/dist/Prisme-macOS.zip"
printf 'Application: %s\n' "$app"
