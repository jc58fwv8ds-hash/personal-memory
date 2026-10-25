#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=/private/tmp/memory-calendar-clang
export SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/memory-calendar-swiftpm
export XDG_CACHE_HOME=/private/tmp/memory-calendar-cache
swift build --disable-sandbox --product MemoryCalendar
# Never replace an earlier development build or an installed app.
bundle_dir="${PWD}/Builds/$(date +%Y%m%d-%H%M%S)/Personal Memory Calendar.app"
mkdir -p "${bundle_dir}/Contents/MacOS"
cp .build/debug/MemoryCalendar "${bundle_dir}/Contents/MacOS/MemoryCalendar"
cp Support/Info.plist "${bundle_dir}/Contents/Info.plist"
codesign --force --sign - "${bundle_dir}"
codesign --verify --deep --strict "${bundle_dir}"
print -r -- "${bundle_dir}"
