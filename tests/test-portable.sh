#!/usr/bin/env bash
set -Eeo pipefail
IFS=$'\n\t'
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/fixtures" "$TMP/home"
for cmd in bash cat chmod cp dirname basename find head awk sed jq mkdir mktemp rm grep wc tr mv ln cmp readlink; do
  ln -s "$(command -v "$cmd")" "$TMP/bin/$cmd"
done
cat > "$TMP/fixtures/tree.json" <<'JSON'
{"sha":"commit-sha","truncated":false,"tree":[{"path":"skills","type":"tree"},{"path":"skills/demo","type":"tree"},{"path":"skills/demo/SKILL.md","type":"blob","mode":"100644"},{"path":"skills/demo/.hidden","type":"blob","mode":"100644"},{"path":"skills/demo/run.sh","type":"blob","mode":"100755"},{"path":"skills/demo/data.bin","type":"blob","mode":"100644"},{"path":"skills/demo/link","type":"blob","mode":"120000","sha":"link-sha"},{"path":"other","type":"tree"},{"path":"other/SKILL.md","type":"blob","mode":"100644"},{"path":"other/unused","type":"blob","mode":"100644"}]}
JSON
cat > "$TMP/fixtures/SKILL.md" <<'MD'
---
name: demo
description: portable fixture
---
Portable fixture
MD
cat > "$TMP/fixtures/curl" <<'CURL'
#!/usr/bin/env bash
set -e
output="/dev/stdout" url="" accept="" auth="" write_status=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -H)
      case "$2" in
        Accept:*) accept="$2" ;;
        Authorization:*) auth="$2" ;;
      esac
      shift 2 ;;
    -w) write_status=1; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$FIXTURES/requests"
if [[ -n "${EXPECT_AUTH:-}" && "$auth" != "Authorization: Bearer $EXPECT_AUTH" ]]; then exit 1; fi
status=200
case "${API_SCENARIO:-}:$url" in
  rate:*) printf '{"message":"API rate limit exceeded"}' > "$output"; status=403 ;;
  denied:*) printf '{"message":"Forbidden"}' > "$output"; status=403 ;;
  truncated:*/git/trees/*) printf '{"sha":"commit-sha","truncated":true,"tree":[]}' > "$output" ;;
  unsafe:*/git/trees/*) printf '{"sha":"commit-sha","truncated":false,"tree":[{"type":"tree","path":"../escape"}]}' > "$output" ;;
  *:*/ai-ecoverse/gh-upskill/main/install.sh) cat "$FIXTURES/install.sh" > "$output" ;;
  *:*/ai-ecoverse/gh-upskill/main/upskill) cat "$FIXTURES/upskill" > "$output" ;;
  *:*/ai-ecoverse/gh-upskill/main/gh-upskill) cat "$FIXTURES/gh-upskill" > "$output" ;;
  *:*/repos/test/repo) printf '{"default_branch":"feature/portable"}' > "$output" ;;
  *:*/commits/*) printf '{"sha":"commit-sha"}' > "$output" ;;
  *:*/git/trees/*) cat "$FIXTURES/tree.json" > "$output" ;;
  *:*/contents/other/SKILL.md*) printf '%s\n' '---' 'name: other' '---' > "$output" ;;
  *:*/contents/*SKILL.md*) cat "$FIXTURES/SKILL.md" > "$output" ;;
  *:*/contents/*data.bin*) printf '\000\001\377' > "$output" ;;
  *:*/contents/*run.sh*) printf '#!/usr/bin/env bash\necho portable\n' > "$output" ;;
  *:*/contents/*.hidden*) printf 'hidden\n' > "$output" ;;
  *:*/git/blobs/link-sha) printf 'run.sh' > "$output" ;;
  *) printf '{"message":"unexpected URL"}' > "$output"; status=404 ;;
esac
if [[ "$url" == */contents/* || "$url" == */git/blobs/* ]]; then
  [[ "$accept" == 'Accept: application/vnd.github.raw+json' ]] || exit 1
fi
if [[ -n "$write_status" ]]; then printf '%s' "$status"; fi
CURL
cp "$ROOT_DIR/install.sh" "$ROOT_DIR/upskill" "$ROOT_DIR/gh-upskill" "$TMP/fixtures/"
cp "$TMP/fixtures/curl" "$TMP/bin/curl"
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin" FIXTURES="$TMP/fixtures" HOME="$TMP/home"
unset GITHUB_TOKEN GH_TOKEN
for cmd in git gh tar unzip rsync python perl; do
  if command -v "$cmd" >/dev/null; then echo "FAIL: $cmd is not hidden"; exit 1; fi
done
"$ROOT_DIR/upskill" test/repo --skill demo --path ./skills/demo/ --dest "$TMP/installed"
test -f "$TMP/installed/demo/SKILL.md"
test -f "$TMP/installed/demo/.hidden"
test -x "$TMP/installed/demo/run.sh"
test -L "$TMP/installed/demo/link"
printf '\000\001\377' > "$TMP/expected.bin"
cmp "$TMP/expected.bin" "$TMP/installed/demo/data.bin"
[[ "$(readlink "$TMP/installed/demo/link")" == run.sh ]]
grep -q '/commits/feature%2Fportable' "$FIXTURES/requests"
if grep -q '/contents/other/' "$FIXTURES/requests"; then echo 'FAIL: downloaded unselected skill files'; exit 1; fi
SLICC_PAGE_LOOPBACK=1 "$ROOT_DIR/upskill" test/repo@main --skill demo
SLICC_PAGE_LOOPBACK=1 "$ROOT_DIR/upskill" read demo > "$TMP/read.log"
grep -q 'Portable fixture' "$TMP/read.log"
SLICC_PAGE_LOOPBACK=1 "$ROOT_DIR/upskill" list > "$TMP/local-list.log"
grep -q '.pi/agent/skills' "$TMP/local-list.log"
test -f "$HOME/.pi/agent/skills/demo/SKILL.md"
SLICC_PAGE_LOOPBACK=1 "$ROOT_DIR/upskill" test/repo@main --skill demo --dest "$TMP/explicit"
test -f "$TMP/explicit/demo/SKILL.md"
"$ROOT_DIR/upskill" test/repo@main --list > "$TMP/list.log"
grep -q 'Available skills' "$TMP/list.log"
GITHUB_TOKEN=test-primary GH_TOKEN=test-secondary EXPECT_AUTH=test-primary "$ROOT_DIR/upskill" test/repo@main --list >/dev/null
GH_TOKEN=test-secondary EXPECT_AUTH=test-secondary "$ROOT_DIR/upskill" test/repo@main --list >/dev/null
for scenario in rate denied truncated unsafe; do
  if API_SCENARIO="$scenario" "$ROOT_DIR/upskill" test/repo@main --all > "$TMP/$scenario.log" 2>&1; then
    echo "FAIL: $scenario should fail"; exit 1
  fi
done
grep -q 'GITHUB_TOKEN or GH_TOKEN' "$TMP/rate.log"
grep -q 'access denied' "$TMP/denied.log"
grep -q 'truncated' "$TMP/truncated.log"
grep -q 'Unsafe path' "$TMP/unsafe.log"
if "$ROOT_DIR/upskill" test/repo@main --path ../escape --all >/dev/null 2>&1; then exit 1; fi
if "$ROOT_DIR/upskill" test/repo@main --path missing/demo --all > "$TMP/missing.log" 2>&1; then exit 1; fi
grep -q 'skills/demo' "$TMP/missing.log"
export PNPM_HOME="$TMP/pnpm" SLICC_PAGE_LOOPBACK=1
export PATH="$PNPM_HOME:$PATH"
curl -fsSL https://raw.githubusercontent.com/ai-ecoverse/gh-upskill/main/install.sh | bash
[[ "$(command -v upskill)" == "$PNPM_HOME/upskill" ]]
upskill test/repo@main --skill demo --dest "$TMP/from-installer"
test -f "$TMP/from-installer/demo/SKILL.md"
bash "$ROOT_DIR/install.sh" --prefix "$TMP/prefix"
test -x "$TMP/prefix/bin/upskill"
echo 'PORTABLE TESTS PASSED'
