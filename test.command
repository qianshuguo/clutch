#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build
/usr/bin/swiftc -module-cache-path "$PWD/build/module-cache" Source/Keyboard/KeyboardState.swift Source/Keyboard/KeyCodes.swift Source/Keyboard/MappingPolicy.swift Source/Windows/WindowLayout.swift Source/Shared/WindowShortcuts.swift Source/Folders/FolderEntry.swift Source/Websites/WebsiteEntry.swift Source/Shared/Persistence.swift Source/Shared/ToolError.swift Tests/main.swift -o build/keyboard-tests
build/keyboard-tests
# View/controller regressions run without the utility's application entry point.
list_sources=(Source/**/*.swift)
list_sources=("${(@)list_sources:#Source/main.swift}")
/usr/bin/swiftc -module-cache-path "$PWD/build/module-cache" "${list_sources[@]}" Tests/Lists/main.swift -o build/list-tests
build/list-tests
