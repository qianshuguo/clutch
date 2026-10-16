#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build HyperKey.app/Contents/MacOS
cp HyperKey-Info.plist HyperKey.app/Contents/Info.plist
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
for arch in arm64 x86_64; do
  /usr/bin/swiftc -O -target "$arch-apple-macosx12.0" -module-cache-path "$PWD/build/module-cache" Source/KeyboardState.swift Source/main.swift -o "build/HyperKey-$arch" -framework Cocoa -framework ApplicationServices -framework Carbon -framework IOKit -framework ServiceManagement
done
/usr/bin/lipo -create build/HyperKey-arm64 build/HyperKey-x86_64 -output HyperKey.app/Contents/MacOS/HyperKey
/usr/bin/codesign --force --sign - --identifier local.maxvoid.HyperKey HyperKey.app
print "已构建：$PWD/HyperKey.app"
