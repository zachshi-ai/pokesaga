#!/usr/bin/env bash
# Build the independently installable Android study edition with Godot 4.7.2.
# On a new machine, configure Godot's Android export tools and debug keystore first.
set -euo pipefail

project=$(cd "$(dirname "$0")/.." && pwd)
destination=${1:-"$project/../outputs/PokeSaga-study.apk"}
mkdir -p "$(dirname "$destination")"
destination=$(cd "$(dirname "$destination")" && pwd)/$(basename "$destination")
staging=$(mktemp -d "$(dirname "$destination")/.pokesaga-apk.XXXXXX")
trap 'rm -rf "$staging"' EXIT

# The local macOS toolchain is optional. GODOT_BIN and the SDK variables
# also work with a separately configured editor on Linux or macOS.
toolchain=${POKESAGA_TOOLCHAIN:-"$HOME/Library/Application Support/PokeSagaBuild"}
editor=${GODOT_BIN:-godot}
if [[ -z ${GODOT_BIN:-} ]] && ! command -v godot >/dev/null && [[ -x "$toolchain/godot/Godot" ]]; then
    editor="$toolchain/godot/Godot"
fi
if [[ -z ${JAVA_HOME:-} && -x "$toolchain/jdk/bin/java" ]]; then
    export JAVA_HOME="$toolchain/jdk"
fi
if [[ -z ${ANDROID_HOME:-} && -d "$toolchain/sdk" ]]; then
    export ANDROID_HOME="$toolchain/sdk"
fi

"$editor" --headless --path "$project" --import
"$editor" --headless --path "$project" --export-debug "Android Study" "$staging/study.apk"
mv -f "$staging/study.apk" "$destination"
printf '%s\n' "$destination"
