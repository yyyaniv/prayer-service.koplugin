#!/usr/bin/env bash
# Build the installable plugin ZIP: dist/molytva.koplugin-<version>.zip
# Usage: tools/make_release.sh [version]   (default: version from molytva_lib/builder.lua)
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(sed -n 's/^local VERSION, SOURCE = "\([^"]*\)".*/\1/p' "${root}/molytva.koplugin/molytva_lib/builder.lua")}"
[ -n "${version}" ] || { echo "cannot detect version" >&2; exit 1; }
out="${root}/dist/molytva.koplugin-${version}.zip"
mkdir -p "${root}/dist"
rm -f "${out}"
cd "${root}"
COPYFILE_DISABLE=1 zip -qrX "${out}" molytva.koplugin -x '*/.DS_Store' '*/._*' '*/__pycache__/*'
echo "${out}"
