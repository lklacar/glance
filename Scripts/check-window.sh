#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${options[@]}" --product Glance
binary_path=$(swift build "${options[@]}" --show-bin-path)
mkdir -p .build/window-checks
swiftc -I "$binary_path/Modules" \
    Sources/Glance/CanvasView.swift Sources/Glance/ViewerWindowController.swift \
    Tests/GlanceWindowChecks/main.swift "$binary_path"/GlanceCore.build/*.swift.o \
    -o .build/window-checks/GlanceWindowChecks
.build/window-checks/GlanceWindowChecks
