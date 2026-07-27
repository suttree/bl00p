#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${APP_VERSION:-0.1.0}

mkdir -p "$project_root/.build/clang-module-cache"
mkdir -p "$project_root/.build/swiftpm-module-cache"
mkdir -p "$project_root/.build/cache"

env \
    CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-module-cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/swiftpm-module-cache" \
    XDG_CACHE_HOME="$project_root/.build/cache" \
    swift build -c release

APP_VERSION="$version" sh "$project_root/scripts/package-deb.sh" release
