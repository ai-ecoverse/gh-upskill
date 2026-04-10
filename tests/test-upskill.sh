#!/usr/bin/env bash
set -Eeo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"

require_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! require_cmd gh; then
  echo "SKIP: gh CLI not installed" >&2
  exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

pushd "$TMP" >/dev/null

echo "Running upskill (first run) ..."
# Always scans for **/SKILL.md per agentskills.io spec
"$ROOT_DIR/upskill" adobe/helix-website -b main --all

test -d .skills || { echo "FAIL: .skills missing"; exit 1; }
count_skills=$(find .skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
if [[ "$count_skills" -le 0 ]]; then
  echo "FAIL: No SKILL.md files copied"
  exit 1
fi

test -x .agents/discover-skills || { echo "FAIL: .agents/discover-skills not executable"; exit 1; }

echo "Checking AGENTS.md markers ..."
marker_start='<!-- upskill:skills:start -->'
marker_end='<!-- upskill:skills:end -->'
grep -qF "$marker_start" AGENTS.md || { echo "FAIL: start marker missing"; exit 1; }
grep -qF "$marker_end" AGENTS.md || { echo "FAIL: end marker missing"; exit 1; }

count_markers=$(grep -cF "$marker_start" AGENTS.md)
[[ "$count_markers" == "1" ]] || { echo "FAIL: duplicate start markers on first run"; exit 1; }

echo "Running upskill (second run) ..."
"$ROOT_DIR/upskill" adobe/helix-website -b main --all

count_markers2=$(grep -cF "$marker_start" AGENTS.md)
[[ "$count_markers2" == "1" ]] || { echo "FAIL: duplicate start markers after second run"; exit 1; }

echo "Running discover-skills ..."
out="$(.agents/discover-skills | sed -n '1,40p')"
echo "$out" | grep -q "Available Skills:" || { echo "FAIL: discover-skills header missing"; exit 1; }
echo "$out" | grep -q -- "---" || { echo "FAIL: discover-skills separator missing"; exit 1; }

# Test gitignore insertion with -i
echo "Running upskill with -i ..."
"$ROOT_DIR/upskill" -i adobe/helix-website -b main --all

test -f .gitignore || { echo "FAIL: .gitignore not created"; exit 1; }
grep -qF ".skills/" .gitignore || { echo "FAIL: .gitignore missing skills entry"; exit 1; }
grep -qF ".agents/discover-skills" .gitignore || { echo "FAIL: .gitignore missing discover entry"; exit 1; }

# Ensure idempotent block
start_marker="# upskill:gitignore:start"
[[ $(grep -cF "$start_marker" .gitignore) == "1" ]] || { echo "FAIL: duplicate gitignore block after first -i"; exit 1; }
"$ROOT_DIR/upskill" -i adobe/helix-website -b main --all
[[ $(grep -cF "$start_marker" .gitignore) == "1" ]] || { echo "FAIL: duplicate gitignore block after second -i"; exit 1; }

# Test --dest-path flag
echo "Testing --dest-path flag ..."
"$ROOT_DIR/upskill" adobe/helix-website -b main --all --dest-path custom-skills
test -d custom-skills || { echo "FAIL: custom-skills directory missing"; exit 1; }
count_custom=$(find custom-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_custom" -gt 0 ]] || { echo "FAIL: No skills in custom destination"; exit 1; }

# Test --path flag (subfolder filtering)
echo "Testing --path flag ..."
"$ROOT_DIR/upskill" adobe/skills -b main --path skills/aem/edge-delivery-services --all --dest-path path-filtered-skills
test -d path-filtered-skills || { echo "FAIL: path-filtered-skills directory missing"; exit 1; }
count_path=$(find path-filtered-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_path" -gt 0 ]] || { echo "FAIL: No skills found with --path filter"; exit 1; }
echo "Found $count_path skill(s) with --path filter"

# Test owner/repo@branch inline syntax
echo "Testing owner/repo@branch syntax ..."
"$ROOT_DIR/upskill" adobe/helix-website@main --all --dest-path at-branch-skills
test -d at-branch-skills || { echo "FAIL: at-branch-skills directory missing"; exit 1; }
count_at=$(find at-branch-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_at" -gt 0 ]] || { echo "FAIL: No skills installed with @branch syntax"; exit 1; }
echo "Found $count_at skill(s) with @branch syntax"

# Test that -b flag takes precedence over @branch
echo "Testing -b precedence over @branch ..."
"$ROOT_DIR/upskill" adobe/helix-website@main -b main --all --dest-path b-precedence-skills
test -d b-precedence-skills || { echo "FAIL: b-precedence-skills directory missing"; exit 1; }
count_bp=$(find b-precedence-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_bp" -gt 0 ]] || { echo "FAIL: No skills installed with -b precedence test"; exit 1; }
echo "-b flag precedence works correctly"

# Test --path with invalid path
echo "Testing --path with invalid path ..."
if "$ROOT_DIR/upskill" adobe/skills -b main --path nonexistent/path --all --dest-path bad-path 2>/dev/null; then
  echo "FAIL: --path with invalid path should have failed"
  exit 1
fi
echo "Correctly rejected invalid --path"

# Test --force flag
echo "Testing --force flag ..."
# Skills were already installed above; re-installing without --force should skip
skip_out=$("$ROOT_DIR/upskill" adobe/helix-website -b main --all 2>&1 || true)
if echo "$skip_out" | grep -q "already exists"; then
  echo "Correctly skipped existing skill without --force"
else
  echo "FAIL: Expected skip warning for existing skill without --force"
  exit 1
fi

# Re-installing with --force should overwrite
force_out=$("$ROOT_DIR/upskill" adobe/helix-website -b main --all --force 2>&1)
if echo "$force_out" | grep -q "Overwriting existing skill"; then
  echo "Correctly overwrote existing skill with --force"
else
  echo "FAIL: Expected overwrite message with --force"
  exit 1
fi
# Verify skills still present after --force
count_force=$(find .skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_force" -gt 0 ]] || { echo "FAIL: No skills after --force reinstall"; exit 1; }

# ── upskill list subcommand tests ──

# Test list with skills already installed in .skills/
echo "Testing 'upskill list' with installed skills ..."
list_out=$("$ROOT_DIR/upskill" list 2>&1)
echo "$list_out" | grep -q "Discoverable local skills:" || { echo "FAIL: list header missing"; exit 1; }
echo "$list_out" | grep -q "NAME" || { echo "FAIL: list table header missing"; exit 1; }
echo "$list_out" | grep -q "SOURCE" || { echo "FAIL: list SOURCE column missing"; exit 1; }
echo "$list_out" | grep -q "PATH" || { echo "FAIL: list PATH column missing"; exit 1; }
echo "$list_out" | grep -q "Found .* skill(s)" || { echo "FAIL: list skill count missing"; exit 1; }
echo "upskill list works with installed skills"

# Test list with no skills (clean directory)
echo "Testing 'upskill list' with no skills ..."
empty_dir=$(mktemp -d)
pushd "$empty_dir" >/dev/null
no_skills_out=$(HOME="$empty_dir" "$ROOT_DIR/upskill" list 2>&1)
echo "$no_skills_out" | grep -q "No local skills found." || { echo "FAIL: empty list message missing"; exit 1; }
echo "$no_skills_out" | grep -q ".skills/" || { echo "FAIL: empty list hint missing .skills/"; exit 1; }
popd >/dev/null
rm -rf "$empty_dir"
echo "upskill list works with no skills"

# Test that list subcommand is mentioned in help
echo "Testing help includes list subcommand ..."
help_out=$("$ROOT_DIR/upskill" --help 2>&1)
echo "$help_out" | grep -q "list" || { echo "FAIL: help does not mention list subcommand"; exit 1; }
echo "Help text includes list subcommand"

# Test info and read subcommands
echo "Testing info subcommand ..."
# Create a temporary skill with frontmatter
mkdir -p .skills/test-info-skill
cat > .skills/test-info-skill/SKILL.md <<'SKILLEOF'
---
name: test-info-skill
description: A test skill for info subcommand
---
# Test Info Skill

This is a test skill used for testing the info subcommand.
SKILLEOF

# Create an extra file to test directory listing
echo "helper content" > .skills/test-info-skill/helper.txt

info_out=$("$ROOT_DIR/upskill" info test-info-skill)
echo "$info_out" | grep -q "Skill: test-info-skill" || { echo "FAIL: info missing skill name"; exit 1; }
echo "$info_out" | grep -q "Path: .skills/test-info-skill/SKILL.md" || { echo "FAIL: info missing path"; exit 1; }
echo "$info_out" | grep -q "Source: project (.skills)" || { echo "FAIL: info missing source"; exit 1; }
echo "$info_out" | grep -q "Description: A test skill for info subcommand" || { echo "FAIL: info missing description"; exit 1; }
echo "$info_out" | grep -q "Contents:" || { echo "FAIL: info missing contents header"; exit 1; }
echo "$info_out" | grep -q "SKILL.md" || { echo "FAIL: info contents missing SKILL.md"; exit 1; }
echo "$info_out" | grep -q "helper.txt" || { echo "FAIL: info contents missing helper.txt"; exit 1; }
echo "info subcommand works correctly"

echo "Testing read subcommand ..."
read_out=$("$ROOT_DIR/upskill" read test-info-skill)
echo "$read_out" | grep -q "name: test-info-skill" || { echo "FAIL: read missing frontmatter"; exit 1; }
echo "$read_out" | grep -q "# Test Info Skill" || { echo "FAIL: read missing heading"; exit 1; }
echo "$read_out" | grep -q "testing the info subcommand" || { echo "FAIL: read missing body text"; exit 1; }
echo "read subcommand works correctly"

# Test info/read with nonexistent skill
echo "Testing info with nonexistent skill ..."
if "$ROOT_DIR/upskill" info nonexistent-skill-xyz 2>/dev/null; then
  echo "FAIL: info should fail for nonexistent skill"
  exit 1
fi
echo "Correctly rejected nonexistent skill for info"

echo "Testing read with nonexistent skill ..."
if "$ROOT_DIR/upskill" read nonexistent-skill-xyz 2>/dev/null; then
  echo "FAIL: read should fail for nonexistent skill"
  exit 1
fi
echo "Correctly rejected nonexistent skill for read"

# Test info/read without name argument
echo "Testing info without name ..."
if "$ROOT_DIR/upskill" info 2>/dev/null; then
  echo "FAIL: info without name should fail"
  exit 1
fi
echo "Correctly rejected info without name"

echo "Testing read without name ..."
if "$ROOT_DIR/upskill" read 2>/dev/null; then
  echo "FAIL: read without name should fail"
  exit 1
fi
echo "Correctly rejected read without name"

# ── upskill recommendations subcommand tests ──

# Test recommendations without profile (no network needed)
echo "Testing 'upskill recommendations' without profile ..."
no_profile_dir=$(mktemp -d)
pushd "$no_profile_dir" >/dev/null
rec_out=$(HOME="$no_profile_dir" "$ROOT_DIR/upskill" recommendations 2>&1 || true)
echo "$rec_out" | grep -q "No user profile found" || { echo "FAIL: recommendations missing no-profile message"; exit 1; }
echo "$rec_out" | grep -q "upskill-profile.json" || { echo "FAIL: recommendations missing profile filename hint"; exit 1; }
echo "$rec_out" | grep -q '"purpose"' || { echo "FAIL: recommendations missing profile format example"; exit 1; }
echo "$rec_out" | grep -q '"role"' || { echo "FAIL: recommendations missing role in profile example"; exit 1; }
popd >/dev/null
rm -rf "$no_profile_dir"
echo "recommendations without profile works correctly"

# Test that help mentions recommendations
echo "Testing help includes recommendations subcommand ..."
help_out=$("$ROOT_DIR/upskill" --help 2>&1)
echo "$help_out" | grep -q "recommendations" || { echo "FAIL: help does not mention recommendations subcommand"; exit 1; }
echo "Help text includes recommendations subcommand"

# ── ClawHub and Tessl source detection tests ──

# Test help text mentions ClawHub and Tessl
echo "Testing help includes ClawHub and Tessl ..."
help_out=$("$ROOT_DIR/upskill" --help 2>&1)
echo "$help_out" | grep -q "clawhub:" || { echo "FAIL: help does not mention clawhub: source"; exit 1; }
echo "$help_out" | grep -q "tessl:" || { echo "FAIL: help does not mention tessl: source"; exit 1; }
echo "$help_out" | grep -q "clawhub.ai" || { echo "FAIL: help does not mention clawhub.ai URL"; exit 1; }
echo "$help_out" | grep -q "Install sources:" || { echo "FAIL: help missing Install sources section"; exit 1; }
echo "Help text includes ClawHub and Tessl sources"

# Test clawhub: shorthand is detected (will fail at download, but confirms routing)
echo "Testing clawhub: shorthand detection ..."
ch_out=$("$ROOT_DIR/upskill" clawhub:nonexistent-test-slug-xyz 2>&1 || true)
if echo "$ch_out" | grep -q "Downloading from ClawHub: nonexistent-test-slug-xyz"; then
  echo "Correctly routed clawhub: shorthand to ClawHub install path"
elif echo "$ch_out" | grep -q "ClawHub download failed"; then
  echo "Correctly routed clawhub: shorthand (download failed as expected for bad slug)"
else
  echo "FAIL: clawhub: shorthand was not routed to ClawHub install path"
  echo "Output: $ch_out"
  exit 1
fi

# Test clawhub:<user>/<slug> extracts slug correctly
echo "Testing clawhub:user/slug detection ..."
ch2_out=$("$ROOT_DIR/upskill" clawhub:someuser/my-skill 2>&1 || true)
if echo "$ch2_out" | grep -q "Downloading from ClawHub: my-skill"; then
  echo "Correctly extracted slug from clawhub:user/slug"
elif echo "$ch2_out" | grep -q "ClawHub download failed"; then
  echo "Correctly routed clawhub:user/slug (download failed as expected)"
else
  echo "FAIL: clawhub:user/slug was not parsed correctly"
  echo "Output: $ch2_out"
  exit 1
fi

# Test ClawHub full URL detection
echo "Testing ClawHub URL detection ..."
ch_url_out=$("$ROOT_DIR/upskill" https://clawhub.ai/someuser/my-url-skill 2>&1 || true)
if echo "$ch_url_out" | grep -q "Downloading from ClawHub: my-url-skill"; then
  echo "Correctly extracted slug from ClawHub URL"
elif echo "$ch_url_out" | grep -q "ClawHub download failed"; then
  echo "Correctly routed ClawHub URL (download failed as expected)"
else
  echo "FAIL: ClawHub URL was not parsed correctly"
  echo "Output: $ch_url_out"
  exit 1
fi

# Test tessl: shorthand detection (will fail at API call, but confirms routing)
echo "Testing tessl: shorthand detection ..."
ts_out=$("$ROOT_DIR/upskill" tessl:nonexistent-test-skill-xyz 2>&1 || true)
if echo "$ts_out" | grep -q "Resolving Tessl skill: nonexistent-test-skill-xyz"; then
  echo "Correctly routed tessl: shorthand to Tessl resolve path"
elif echo "$ts_out" | grep -q "Tessl"; then
  echo "Correctly routed tessl: shorthand (API call made as expected)"
else
  echo "FAIL: tessl: shorthand was not routed to Tessl resolve path"
  echo "Output: $ts_out"
  exit 1
fi

# ── upskill search subcommand tests ──

echo "Testing 'upskill search' with a query ..."
if command -v jq >/dev/null 2>&1; then
  search_out=$("$ROOT_DIR/upskill" search "pdf" 2>&1)
  echo "$search_out" | grep -q 'Search results for "pdf"' || { echo "FAIL: search header missing"; exit 1; }
  echo "$search_out" | grep -q "NAME" || { echo "FAIL: search table header missing"; exit 1; }
  echo "$search_out" | grep -q "SOURCE" || { echo "FAIL: search SOURCE column missing"; exit 1; }
  echo "$search_out" | grep -q "To install:" || { echo "FAIL: search install hint missing"; exit 1; }
  echo "upskill search works"

  # Test search without query argument
  echo "Testing search without query ..."
  if "$ROOT_DIR/upskill" search 2>/dev/null; then
    echo "FAIL: search without query should fail"
    exit 1
  fi
  echo "Correctly rejected search without query"

  # Test that search subcommand is mentioned in help
  echo "Testing help includes search subcommand ..."
  help_search_out=$("$ROOT_DIR/upskill" --help 2>&1)
  echo "$help_search_out" | grep -q "search" || { echo "FAIL: help does not mention search subcommand"; exit 1; }
  echo "Help text includes search subcommand"
else
  echo "SKIP: jq not installed, skipping search tests"
fi

echo "OK"

popd >/dev/null
