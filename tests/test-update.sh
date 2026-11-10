#!/usr/bin/env bash
# Offline tests for install tracking (.upskill markers), in-place updates,
# `upskill outdated` and `upskill update`. A fake curl serves a fixture
# repository with three commits, modelled on the slack skill's history:
#   C1  skills/slack has scripts/slack-support.jsh
#   C2  skills/slack replaces it with scripts/slack-support (executable)
#   C3  touches only README.md, so skills/slack's latest commit stays C2
# Run against another build with UPSKILL=/path/to/upskill.
set -Eeo pipefail
IFS=$'\n\t'
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPSKILL="${UPSKILL:-$ROOT_DIR/upskill}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

C1=1111111111111111111111111111111111111111
C2=2222222222222222222222222222222222222222
C3=3333333333333333333333333333333333333333
FIX="$TMP/fixtures"
mkdir -p "$TMP/bin" "$TMP/bin-jq" "$TMP/bin-unzip" "$TMP/home"

# --- fixture repository -------------------------------------------------------
skill_md() {
  printf -- '---\nname: %s\ndescription: %s\n---\n%s\n' "$1" "$2" "$3"
}
mkrepo() {
  local dir="$FIX/commits/$1"
  mkdir -p "$dir/skills/slack/scripts" "$dir/skills/slack/references" "$dir/skills/other"
  printf 'readme %s\n' "$1" > "$dir/README.md"
  skill_md other 'other skill' 'other body' > "$dir/skills/other/SKILL.md"
  printf 'manifest\n' > "$dir/skills/slack/references/app-manifest.md"
  printf 'slack.jsh\n' > "$dir/skills/slack/scripts/slack.jsh"
}
mkrepo "$C1"
skill_md slack 'slack skill' 'slack v1' > "$FIX/commits/$C1/skills/slack/SKILL.md"
printf 'old support\n' > "$FIX/commits/$C1/skills/slack/scripts/slack-support.jsh"
printf 'TOKEN=template-v1\n' > "$FIX/commits/$C1/skills/slack/scripts/.config"
for c in "$C2" "$C3"; do
  mkrepo "$c"
  skill_md slack 'slack skill' 'slack v2' > "$FIX/commits/$c/skills/slack/SKILL.md"
  printf '#!/usr/bin/env bash\necho support\n' > "$FIX/commits/$c/skills/slack/scripts/slack-support"
  chmod 755 "$FIX/commits/$c/skills/slack/scripts/slack-support"
  printf 'TOKEN=template-v2\n' > "$FIX/commits/$c/skills/slack/scripts/.config"
done
printf '%s\n' "$C1" "$C2" "$C3" > "$FIX/order"

set_head() { printf '%s' "$1" > "$FIX/head"; }
reset_remote() {
  set_head "$C1"
  : > "$FIX/requests"
}

cat > "$TMP/fake-curl" <<'CURL'
#!/usr/bin/env bash
set -e
PATH="$HOST_PATH"
output="/dev/stdout" url="" write_status=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -H) shift 2 ;;
    -w) write_status=1; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >> "$FIXTURES/requests"
head_sha=$(cat "$FIXTURES/head")
status=200
index_of() { grep -nx "$1" "$FIXTURES/order" | cut -d: -f1 || true; }
query_param() { printf '%s' "$url" | sed -n "s/.*[?&]$1=\([^&]*\).*/\1/p" | sed 's/%2F/\//g'; }
case "$url" in
  https://api.github.com/repos/test/repo)
    printf '{"default_branch":"main"}' > "$output" ;;
  https://api.github.com/repos/test/repo/commits\?*)
    # Latest commit touching the path, walking history up to the given ref.
    path=$(query_param path) ref=$(query_param sha)
    [[ -n "$ref" && "$ref" != main ]] || ref=$head_sha
    upto=$(index_of "$ref")
    if [[ -z "$upto" ]]; then printf '{"message":"No commit found for SHA: %s"}' "$ref" > "$output"; status=422
    else
      sha="" prev=""
      while IFS= read -r c; do
        if [[ -z "$sha" ]] || ! diff -r "$FIXTURES/commits/$prev/$path" "$FIXTURES/commits/$c/$path" >/dev/null 2>&1; then sha=$c; fi
        prev=$c
      done < <(head -n "$upto" "$FIXTURES/order")
      printf '[{"sha":"%s","node_id":"x","commit":{"tree":{"sha":"ffffffffffffffffffffffffffffffffffffffff"}}}]' "$sha" > "$output"
    fi ;;
  https://api.github.com/repos/test/repo/commits/*)
    ref="${url##*/commits/}"
    if [[ "$ref" == main ]]; then ref=$head_sha; fi
    if [[ -d "$FIXTURES/commits/$ref" ]]; then printf '{"sha":"%s"}' "$ref" > "$output"
    else printf '{"message":"No commit found"}' > "$output"; status=422; fi ;;
  https://api.github.com/repos/test/repo/git/trees/*)
    sha="${url##*/git/trees/}"; sha="${sha%%\?*}"
    (cd "$FIXTURES/commits/$sha" && find . -mindepth 1 | sed 's|^\./||' | sort | while IFS= read -r p; do
      if [[ -d "$p" ]]; then printf '{"path":"%s","type":"tree"}\n' "$p"
      elif [[ -x "$p" ]]; then printf '{"path":"%s","type":"blob","mode":"100755"}\n' "$p"
      else printf '{"path":"%s","type":"blob","mode":"100644"}\n' "$p"; fi
    done) | jq -s --arg sha "$sha" '{sha: $sha, truncated: false, tree: .}' > "$output" ;;
  https://api.github.com/repos/test/repo/contents/*)
    path="${url##*/contents/}"; ref="${path##*\?ref=}"; path="${path%%\?*}"
    cat "$FIXTURES/commits/$ref/$path" > "$output" ;;
  https://codeload.github.com/test/repo/zip/refs/heads/main)
    printf '%s' "$head_sha" > "$output" ;;
  */api/v1/download\?*)
    printf 'clawhub-zip' > "$output" ;;
  */api/v1/skills/demo*)
    printf '{"skill":{"slug":"demo"},"latestVersion":{"version":"%s"}}' "$(cat "$FIXTURES/clawhub-latest")" > "$output" ;;
  *) printf '{"message":"unexpected URL"}' > "$output"; status=404 ;;
esac
if [[ -n "$write_status" ]]; then printf '%s' "$status"; fi
CURL

# Fake unzip: the "archive" is a file holding a commit sha (GitHub ZIPs carry
# the commit sha as their archive comment); ClawHub archives come from a dir.
cat > "$TMP/bin-unzip/unzip" <<'UNZIP'
#!/usr/bin/env bash
set -e
PATH="$HOST_PATH"
mode="$1" zip="$2"
content=$(cat "$zip")
if [[ "$content" == clawhub-zip ]]; then
  case "$mode" in
    -l) printf '%s\n' 'Archive: x' ' Length Date Time Name' '------' '1 2026-01-01 00:00 SKILL.md' ;;
    -z) printf 'Archive:  %s\n' "$zip" ;;
    -q) mkdir -p "$4" && cp -R "$FIXTURES/clawhub/." "$4/" ;;
  esac
  exit 0
fi
case "$mode" in
  -l) printf '%s\n' 'Archive: x' ' Length Date Time Name' '------' '1 2026-01-01 00:00 repo-main/README.md' ;;
  -z) printf 'Archive:  %s\n%s\n' "$zip" "$content" ;;
  -q) mkdir -p "$4/repo-main" && cp -R "$FIXTURES/commits/$content/." "$4/repo-main/" ;;
  *) exit 1 ;;
esac
UNZIP

for cmd in uname bash cat chmod cp dirname basename find head tail awk sed mkdir mktemp rm rmdir grep wc tr mv ln cmp readlink date sort cut env ls stat; do
  ln -s "$(command -v "$cmd")" "$TMP/bin/$cmd"
done
ln -s "$(command -v jq)" "$TMP/bin-jq/jq"
cp "$TMP/fake-curl" "$TMP/bin/curl"
chmod +x "$TMP/bin/curl" "$TMP/bin-unzip/unzip"

export HOST_PATH="$PATH" FIXTURES="$FIX" HOME="$TMP/home"
unset GITHUB_TOKEN GH_TOKEN PNPM_HOME SLICC_PAGE_LOOPBACK
API_PATH="$TMP/bin:$TMP/bin-jq"           # curl + jq, no unzip: REST API path
ZIP_PATH="$TMP/bin:$TMP/bin-unzip"        # unzip, no jq: ZIP path
JQ="$(command -v jq)"

# --- harness ------------------------------------------------------------------
FAILED=() PASSED=0
fail() { printf '    FAIL: %s\n' "$*" >&2; return 1; }
run() { PATH="$API_PATH" "$UPSKILL" "$@"; }
run_zip() { PATH="$ZIP_PATH" "$UPSKILL" "$@"; }
mjq() { "$JQ" -r "$1" "$2/.upskill"; }
check() {
  local name="$1"
  shift
  printf 'Test: %s ... ' "$name"
  reset_remote
  local dir="$TMP/case-$((PASSED + ${#FAILED[@]}))" rc
  mkdir -p "$dir"
  set +e
  (cd "$dir" && set -e && "$@") > "$dir.log" 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]] && ! grep -q '    FAIL:' "$dir.log"; then
    PASSED=$((PASSED + 1))
    echo ok
  else
    FAILED+=("$name")
    echo FAILED
    sed 's/^/    /' "$dir.log"
  fi
}
add_state() {
  printf '{"ts":"1"}\n' > "$1/.last-post-C123.json"
  printf '{"watch":1}\n' > "$1/.watch-C123.json"
  printf '{"emoji":"cache"}\n' > "$1/emoji-cache.json"
  printf 'my notes\n' > "$1/scripts/notes.txt"
}
state_intact() {
  grep -q '"ts":"1"' "$1/.last-post-C123.json" || fail ".last-post state lost"
  grep -q '"watch":1' "$1/.watch-C123.json" || fail ".watch state lost"
  grep -q 'cache' "$1/emoji-cache.json" || fail "emoji-cache.json lost"
  grep -q 'my notes' "$1/scripts/notes.txt" || fail "untracked scripts/notes.txt lost"
}
is_v2() {
  test -f "$1/scripts/slack-support" || fail "new scripts/slack-support missing"
  test -x "$1/scripts/slack-support" || fail "scripts/slack-support not executable"
  test ! -e "$1/scripts/slack-support.jsh" || fail "scripts/slack-support.jsh deleted upstream but still present"
  grep -q 'slack v2' "$1/SKILL.md" || fail "SKILL.md not updated"
}

# --- tests --------------------------------------------------------------------
t_marker_resolved_sha() {
  run test/repo --skill slack --dest D
  test -f D/slack/.upskill || fail "no .upskill marker written"
  [[ "$(mjq .kind D/slack)" == github ]] || fail "kind"
  [[ "$(mjq .source D/slack)" == test/repo ]] || fail "source"
  [[ "$(mjq .skill D/slack)" == slack ]] || fail "skill"
  [[ "$(mjq .path D/slack)" == skills/slack ]] || fail "path"
  [[ "$(mjq .sha D/slack)" == "$C1" ]] || fail "sha is not the resolved commit: $(mjq .sha D/slack)"
  [[ "$(mjq .version D/slack)" == 1 ]] || fail "version"
  [[ "$(mjq '.ref // "none"' D/slack)" == none ]] || fail "ref recorded without --branch"
  mjq .installed D/slack | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$' || fail "installed timestamp"
  [[ "$(mjq '.files | join(",")' D/slack)" == "SKILL.md,references/app-manifest.md,scripts/.config,scripts/slack-support.jsh,scripts/slack.jsh" ]] || fail "files: $(mjq '.files | join(",")' D/slack)"
}

t_marker_ref_with_branch() {
  run test/repo -b main --skill slack --dest D
  [[ "$(mjq .ref D/slack)" == main ]] || fail "ref not recorded"
  [[ "$(mjq .sha D/slack)" == "$C1" ]] || fail "sha must be the commit, not the branch: $(mjq .sha D/slack)"
}

t_marker_zip_path_without_jq() {
  run_zip test/repo --skill slack --dest D
  [[ "$(mjq .sha D/slack)" == "$C1" ]] || fail "ZIP install did not record the commit from the archive"
  [[ "$(mjq .path D/slack)" == skills/slack ]] || fail "path"
  [[ "$(mjq '.files | length' D/slack)" == 5 ]] || fail "files"
}

t_update_removes_deleted_file() {
  run test/repo --skill slack --dest D
  set_head "$C3"
  run update slack --dest D
  is_v2 D/slack
  [[ "$(mjq .sha D/slack)" == "$C3" ]] || fail "marker sha not advanced"
  mjq '.files[]' D/slack | grep -qx scripts/slack-support || fail "marker files not updated"
  if mjq '.files[]' D/slack | grep -qx scripts/slack-support.jsh; then fail "marker still lists removed file"; fi
}

t_update_keeps_state() {
  run test/repo --skill slack --dest D
  add_state D/slack
  printf 'TOKEN=secret\n' > D/slack/scripts/.config
  set_head "$C3"
  run update slack --dest D
  is_v2 D/slack
  state_intact D/slack
  grep -q secret D/slack/scripts/.config || fail "existing dotfile (credentials) overwritten"
}

t_reinstall_updates_in_place() {
  run test/repo --skill slack --dest D
  add_state D/slack
  set_head "$C3"
  run test/repo --skill slack --dest D
  is_v2 D/slack
  state_intact D/slack
  [[ "$(mjq .sha D/slack)" == "$C3" ]] || fail "marker sha"
}

t_no_marker_keeps_old_behaviour() {
  run test/repo --skill slack --dest D
  rm -f D/slack/.upskill
  add_state D/slack
  set_head "$C3"
  run test/repo --skill slack --dest D 2> skip.log
  grep -q 'already exists' skip.log || fail "unmarked skill was not skipped"
  test -f D/slack/scripts/slack-support.jsh || fail "unmarked skill modified"
  run test/repo --skill slack --dest D --force
  is_v2 D/slack
  test ! -e D/slack/emoji-cache.json || fail "--force without marker should replace the folder"
}

slicc6_layout() {
  mkdir -p "$1/slack"
  cp -R "$FIX/commits/$C1/skills/slack/." "$1/slack/"
  add_state "$1/slack"
}

t_slicc6_marker_compact() {
  slicc6_layout S
  printf '{"kind":"github","source":"test/repo","skill":"slack","path":"skills/slack","sha":"%s","version":1,"installed":"2026-10-27T17:43:51.429Z","files":["SKILL.md","references/app-manifest.md","scripts/.config","scripts/slack-support.jsh","scripts/slack.jsh"]}' "$C1" > S/slack/.upskill
  run list --dest S > list.log
  grep -q 'test/repo@1111111' list.log || fail "list does not show source@sha: $(cat list.log)"
  run info slack --dest S > info.log
  grep -q 'github:test/repo' info.log || fail "info does not show source: $(cat info.log)"
  grep -q '1111111' info.log || fail "info does not show sha"
  set_head "$C3"
  run outdated --dest S > outdated.log
  grep -q slack outdated.log || fail "outdated does not list SLICC 6 skill: $(cat outdated.log)"
  run update slack --dest S
  is_v2 S/slack
  state_intact S/slack
  [[ "$(mjq .sha S/slack)" == "$C3" ]] || fail "marker sha"
}

t_slicc6_marker_pretty() {
  slicc6_layout S
  cat > S/slack/.upskill <<JSON
{
  "kind": "github",
  "source": "test/repo",
  "skill": "slack",
  "path": "skills/slack",
  "sha": "$C1",
  "files": [
    "SKILL.md",
    "references/app-manifest.md",
    "scripts/slack-support.jsh",
    "scripts/slack.jsh"
  ],
  "version": 1,
  "installed": "2026-10-27T17:43:51.429Z"
}
JSON
  run list --dest S > list.log
  grep -q 'test/repo@1111111' list.log || fail "list: $(cat list.log)"
  set_head "$C2"
  run update --all --dest S
  is_v2 S/slack
  state_intact S/slack
}

t_outdated_fixture() {
  run test/repo --skill slack --skill other --dest D
  set_head "$C3"
  run outdated --dest D > out.log
  grep -Eq '^ *slack +1111111 +2222222' out.log || fail "slack not reported 1111111 -> 2222222: $(cat out.log)"
  if grep -q '^ *other ' out.log; then fail "other is current but reported: $(cat out.log)"; fi
  run update --all --dest D
  run outdated --dest D > after.log
  if grep -Eq '^ *(slack|other) ' after.log; then fail "still outdated after update: $(cat after.log)"; fi
  # Marker at head C3 is ahead of the path's latest commit C2: not outdated.
  [[ "$(mjq .sha D/slack)" == "$C3" ]] || fail "marker sha after update"
  run outdated --dest D > ahead.log
  if grep -q '^ *slack ' ahead.log; then fail "marker ahead of path commit reported outdated"; fi
}

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
t_update_keeps_folder_modes() {
  umask 022
  run test/repo --skill slack --dest D
  [[ "$(mode_of D/slack)" == 755 ]] || fail "installed folder is $(mode_of D/slack)"
  set_head "$C3"
  # sudo keeps the caller's umask, such as seven's 077: a root update of a
  # global skill must leave it as readable as it was.
  (umask 077 && run update slack --dest D)
  is_v2 D/slack
  [[ "$(mode_of D/slack)" == 755 ]] || fail "updated folder is $(mode_of D/slack), not 755"
  [[ "$(mode_of D/slack/scripts)" == 755 ]] || fail "updated scripts/ is $(mode_of D/slack/scripts)"
  [[ "$(mode_of D/slack/SKILL.md)" == 644 ]] || fail "updated SKILL.md is $(mode_of D/slack/SKILL.md)"
  [[ "$(mode_of D/slack/scripts/slack-support)" == 755 ]] || fail "updated script is $(mode_of D/slack/scripts/slack-support)"
  [[ "$(mode_of D/slack/.upskill)" == 644 ]] || fail "updated marker is $(mode_of D/slack/.upskill)"
  chmod 750 D/slack
  set_head "$C1"
  run update slack --dest D --force
  [[ "$(mode_of D/slack)" == 750 ]] || fail "an update changed the folder's mode 750 to $(mode_of D/slack)"
  [[ "$(mode_of D/slack/SKILL.md)" == 640 ]] || fail "SKILL.md in a 750 folder is $(mode_of D/slack/SKILL.md)"
}

t_install_takes_destination_modes() {
  umask 022
  mkdir -p D
  chmod 755 D
  (umask 077 && run test/repo --skill slack --dest D)
  [[ "$(mode_of D/slack)" == 755 ]] || fail "a skill installed into a 755 folder is $(mode_of D/slack)"
  [[ "$(mode_of D/slack/references)" == 755 ]] || fail "references/ is $(mode_of D/slack/references)"
  [[ "$(mode_of D/slack/SKILL.md)" == 644 ]] || fail "SKILL.md is $(mode_of D/slack/SKILL.md)"
  mkdir -p P && chmod 700 P
  run test/repo --skill slack --dest P
  [[ "$(mode_of P/slack)" == 700 ]] || fail "a skill installed into a 700 folder is $(mode_of P/slack)"
  [[ "$(mode_of P/slack/SKILL.md)" == 600 ]] || fail "its SKILL.md is $(mode_of P/slack/SKILL.md)"
}

t_update_errors() {
  if run update --dest D 2>/dev/null; then fail "update without names or --all should fail"; fi
  mkdir -p D/plain && skill_md plain p p > D/plain/SKILL.md
  if run update plain --dest D 2> err.log; then fail "update of unmarked skill should fail"; fi
  grep -q 'marker' err.log || fail "error should mention the missing marker: $(cat err.log)"
}

t_clawhub_marker() {
  mkdir -p "$FIX/clawhub/scripts"
  skill_md demo demo demo > "$FIX/clawhub/SKILL.md"
  printf 'x\n' > "$FIX/clawhub/scripts/run.sh"
  printf '{"ownerId":"o","slug":"demo","version":"1.2.0","publishedAt":1}\n' > "$FIX/clawhub/_meta.json"
  printf '1.2.0' > "$FIX/clawhub-latest"
  PATH="$ZIP_PATH:$TMP/bin-jq" "$UPSKILL" clawhub:someuser/demo --dest D
  [[ "$(mjq .kind D/demo)" == clawhub ]] || fail "kind"
  [[ "$(mjq .source D/demo)" == someuser/demo ]] || fail "source"
  [[ "$(mjq .release D/demo)" == 1.2.0 ]] || fail "release"
  test ! -e D/demo/_meta.json || fail "_meta.json copied"
  printf '1.3.0' > "$FIX/clawhub-latest"
  PATH="$ZIP_PATH:$TMP/bin-jq" "$UPSKILL" outdated --dest D > out.log
  grep -Eq '^ *demo +1\.2\.0 +1\.3\.0' out.log || fail "clawhub outdated: $(cat out.log)"
}

check "marker written with the resolved sha" t_marker_resolved_sha
check "marker records ref with --branch" t_marker_ref_with_branch
check "marker sha from ZIP archive (no jq)" t_marker_zip_path_without_jq
check "update removes a file deleted upstream" t_update_removes_deleted_file
check "update keeps untracked state files" t_update_keeps_state
check "reinstall over a marker updates in place" t_reinstall_updates_in_place
check "no marker: skip, or replace with --force" t_no_marker_keeps_old_behaviour
check "reads a SLICC 6 marker (compact)" t_slicc6_marker_compact
check "reads a SLICC 6 marker (pretty-printed)" t_slicc6_marker_pretty
check "outdated against a fixture" t_outdated_fixture
check "update keeps the skill folder's modes" t_update_keeps_folder_modes
check "install takes the destination's modes" t_install_takes_destination_modes
check "update argument errors" t_update_errors
check "ClawHub marker and outdated" t_clawhub_marker

echo ""
echo "$PASSED passed, ${#FAILED[@]} failed"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '  failed: %s\n' "${FAILED[@]}"
  exit 1
fi
echo 'UPDATE TESTS PASSED'
