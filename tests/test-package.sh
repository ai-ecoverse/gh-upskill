#!/usr/bin/env bash
# The npm package: what it ships, its bins, and the version it reports.
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v npm >/dev/null 2>&1 || { echo "SKIP: npm not installed" >&2; exit 0; }
[[ -f "$ROOT_DIR/package.json" ]] || fail "package.json missing"

echo "Package test: npm pack ships upskill and gh-upskill only ..."
mkdir -p "$TMP/src"
(cd "$ROOT_DIR" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -C "$TMP/src" -xf -
(cd "$TMP/src" && npm version 9.8.7 --no-git-tag-version --allow-same-version >/dev/null)
(cd "$TMP/src" && npm pack --silent --pack-destination "$TMP" >/dev/null)
tarball="$TMP/ai-ecoverse-gh-upskill-9.8.7.tgz"
[[ -f "$tarball" ]] || fail "npm pack wrote no $tarball"

files=$(tar -tzf "$tarball" | sed 's,^package/,,' | LC_ALL=C sort | tr '\n' ' ')
[[ "$files" == "LICENSE README.md gh-upskill kernel/upskill.mjs package.json upskill " ]] || fail "unexpected files: $files"

for bin in upskill gh-upskill; do
  mode=$(tar -tvzf "$tarball" "package/$bin" | awk '{print $1}')
  [[ "$mode" == -rwxr-xr-x ]] || fail "$bin is $mode in the tarball, not executable"
done

mkdir -p "$TMP/unpacked"
tar -C "$TMP/unpacked" -xzf "$tarball"
manifest="$TMP/unpacked/package/package.json"
# shellcheck disable=SC2016
node -e '
  const m = require(process.argv[1]);
  const want = (what, got, expected) => {
    if (JSON.stringify(got) !== JSON.stringify(expected)) {
      console.error(`FAIL: ${what} is ${JSON.stringify(got)}, not ${JSON.stringify(expected)}`);
      process.exit(1);
    }
  };
  want("name", m.name, "@ai-ecoverse/gh-upskill");
  want("bin", m.bin, { upskill: "upskill", "gh-upskill": "gh-upskill" });
  const kernel = { abi: "js", module: "kernel/upskill.mjs" };
  want("slicc.commands", m.slicc?.commands, { upskill: kernel, "gh-upskill": kernel });
  want("publishConfig", m.publishConfig, { access: "public", provenance: true });
  want("scripts", Object.keys(m.scripts ?? {}).filter((s) => /^(pre|post)?install$|^prepare$/.test(s)), []);
' "$manifest"

head -n 1 "$TMP/unpacked/package/upskill" | grep -qx '#!/usr/bin/env bash' || fail "upskill has no bash shebang"
grep -q '^VERSION="9.8.7"$' "$TMP/unpacked/package/upskill" || fail "the packed upskill doesn't carry the package version"
grep -q '^VERSION="9.8.7"$' "$TMP/src/upskill" || fail "prepack didn't stamp the version"
git -C "$ROOT_DIR" diff --quiet -- upskill || fail "packing changed the checkout's upskill"

echo "Package test: npm install -g runs both bins ..."
npm install --global --prefix "$TMP/prefix" --ignore-scripts --no-audit --no-fund "$tarball" >/dev/null
[[ "$("$TMP/prefix/bin/upskill" --version)" == "upskill 9.8.7" ]] || fail "upskill --version: $("$TMP/prefix/bin/upskill" --version)"
[[ "$("$TMP/prefix/bin/gh-upskill" --version)" == "upskill 9.8.7" ]] || fail "gh-upskill --version: $("$TMP/prefix/bin/gh-upskill" --version)"
PATH="$TMP/prefix/bin:$PATH" upskill --help | grep -q 'outdated' || fail "upskill --help lists no outdated"

echo "Package test: an unversioned checkout packs without stamping ..."
mkdir -p "$TMP/dev"
(cd "$ROOT_DIR" && git ls-files -z -co --exclude-standard | tar --null -T - -cf -) | tar -C "$TMP/dev" -xf -
before=$(grep '^VERSION=' "$TMP/dev/upskill")
(cd "$TMP/dev" && npm pack --silent --dry-run >/dev/null)
[[ "$(grep '^VERSION=' "$TMP/dev/upskill")" == "$before" ]] || fail "packing 0.0.0 stamped $(grep '^VERSION=' "$TMP/dev/upskill")"

echo "PACKAGE TEST PASSED"
