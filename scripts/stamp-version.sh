#!/usr/bin/env bash
# prepack: write the package's version into upskill, so the published
# `upskill --version` matches npm. A checkout's 0.0.0 leaves it alone.
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
version=$(node -p 'require("./package.json").version')
[[ "$version" != 0.0.0 ]] || exit 0
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]] || { echo "stamp-version: bad version $version" >&2; exit 1; }
grep -q '^VERSION="[^"]*"$' upskill || { echo 'stamp-version: no VERSION= line in upskill' >&2; exit 1; }
tmp=$(mktemp)
sed "s/^VERSION=\"[^\"]*\"$/VERSION=\"$version\"/" upskill > "$tmp"
cat "$tmp" > upskill
rm -f "$tmp"
