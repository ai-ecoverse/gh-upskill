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
no_skills_out=$("$ROOT_DIR/upskill" list 2>&1)
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

echo "OK"

popd >/dev/null
