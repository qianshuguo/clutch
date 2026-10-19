#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build HyperCaps.app/Contents/MacOS
cp HyperCaps-Info.plist HyperCaps.app/Contents/Info.plist
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
sources=(Source/**/*.swift)
for arch in arm64 x86_64; do
  /usr/bin/swiftc -O -target "$arch-apple-macosx12.0" -module-cache-path "$PWD/build/module-cache" "${sources[@]}" -o "build/HyperCaps-$arch" -framework Cocoa -framework ApplicationServices -framework Carbon -framework IOKit -framework ServiceManagement
done
/usr/bin/lipo -create build/HyperCaps-arm64 build/HyperCaps-x86_64 -output HyperCaps.app/Contents/MacOS/HyperCaps
# Ad-hoc signatures change on every build, so macOS drops the Accessibility grant.
# For a grant that survives rebuilds, create a Code Signing certificate once
# (Keychain Access > Certificate Assistant > Create a Certificate…) and run:
#   HYPERCAPS_SIGN_IDENTITY="HyperCaps Local" ./build.command
identity="${HYPERCAPS_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$identity" --identifier local.maxvoid.HyperCaps HyperCaps.app
print "已构建：$PWD/HyperCaps.app"
