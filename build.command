#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build Clutch.app/Contents/MacOS
cp Clutch-Info.plist Clutch.app/Contents/Info.plist
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
sources=(Source/**/*.swift)
for arch in arm64 x86_64; do
  /usr/bin/swiftc -O -target "$arch-apple-macosx12.0" -module-cache-path "$PWD/build/module-cache" "${sources[@]}" -o "build/Clutch-$arch" -framework Cocoa -framework ApplicationServices -framework Carbon -framework IOKit -framework ServiceManagement
done
/usr/bin/lipo -create build/Clutch-arm64 build/Clutch-x86_64 -output Clutch.app/Contents/MacOS/Clutch
# Ad-hoc signatures change on every build, so macOS drops the Accessibility grant.
# For a grant that survives rebuilds, create a Code Signing certificate once
# (Keychain Access > Certificate Assistant > Create a Certificate…) and run:
#   CLUTCH_SIGN_IDENTITY="Clutch Local" ./build.command
identity="${CLUTCH_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$identity" --identifier local.maxvoid.Clutch Clutch.app
print "已构建：$PWD/Clutch.app"
