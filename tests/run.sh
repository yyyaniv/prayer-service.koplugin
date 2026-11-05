#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="${test_dir}/../molytva.koplugin"
lua_bin="${LUA_BIN:-${HOME}/.local/src/lua-5.1.5/src/lua}"
luac_bin="${LUAC_BIN:-${HOME}/.local/src/lua-5.1.5/src/luac}"

export LUA_PATH="${plugin_dir}/?.lua;${plugin_dir}/?/init.lua;;"
export MOLYTVA_TEST_DIR="${test_dir}"

count=0
while IFS= read -r -d '' file; do
    "${luac_bin}" -p "${file}"
    count=$((count + 1))
done < <(find "${plugin_dir}" -type f -name '*.lua' -print0)
printf 'Syntax OK: %d plugin Lua files\n' "${count}"

for test_file in "${test_dir}"/test_*.lua; do
    "${lua_bin}" "${test_file}"
done
