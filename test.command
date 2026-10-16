#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
/usr/bin/swiftc -module-cache-path "$PWD/build/module-cache" Source/KeyboardState.swift Tests/main.swift -o build/keyboard-tests
build/keyboard-tests
