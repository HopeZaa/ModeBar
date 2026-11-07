#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 HopeZaa
set -euo pipefail
cd -- "${0:A:h}"
BUILD_DIR="${1:-build}"
mkdir -p "$BUILD_DIR/ModeBar.app/Contents/MacOS" "$BUILD_DIR/ModeBar.app/Contents/Resources" "$BUILD_DIR/module-cache"
swiftc -swift-version 5 -O -parse-as-library \
    -target arm64-apple-macosx14.0 \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -framework UniformTypeIdentifiers \
    Sources/*.swift Tests/SelfTests.swift -o "$BUILD_DIR/ModeBar.app/Contents/MacOS/ModeBar"
cp Resources/Info.plist "$BUILD_DIR/ModeBar.app/Contents/Info.plist"
if [[ -f Resources/ModeBar.icns ]]; then
    cp Resources/ModeBar.icns "$BUILD_DIR/ModeBar.app/Contents/Resources/ModeBar.icns"
fi
printf 'APPL????' > "$BUILD_DIR/ModeBar.app/Contents/PkgInfo"
codesign --force --sign - --identifier org.modebar.ModeBar "$BUILD_DIR/ModeBar.app"
echo "Built $BUILD_DIR/ModeBar.app"
