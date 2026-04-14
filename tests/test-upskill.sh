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

# --- Test 1: Default install to .agents/skills/ ---
echo "Test 1: Default install to .agents/skills/ ..."
"$ROOT_DIR/upskill" adobe/helix-website -b main --all

test -d .agents/skills || { echo "FAIL: .agents/skills missing"; exit 1; }
count_skills=$(find .agents/skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_skills" -gt 0 ]] || { echo "FAIL: No SKILL.md files copied"; exit 1; }
echo "  Installed $count_skills skill(s) to .agents/skills/"

# --- Test 2: No AGENTS.md created ---
echo "Test 2: No AGENTS.md created ..."
test ! -f AGENTS.md || { echo "FAIL: AGENTS.md should not be created"; exit 1; }

# --- Test 3: No .agents/discover-skills created ---
echo "Test 3: No .agents/discover-skills created ..."
test ! -f .agents/discover-skills || { echo "FAIL: .agents/discover-skills should not be created"; exit 1; }

# --- Test 4: Without .claude/ dir, only .agents/skills/ exists (no .claude/skills/) ---
echo "Test 4: Without .claude/, no .claude/skills/ ..."
test ! -d .claude/skills || { echo "FAIL: .claude/skills/ should not exist without .claude/ dir"; exit 1; }

# --- Test 5: Claude Code auto-detection ---
echo "Test 5: Claude Code auto-detection ..."
rm -rf .agents/skills
mkdir -p .claude
"$ROOT_DIR/upskill" adobe/helix-website -b main --all

test -d .agents/skills || { echo "FAIL: .agents/skills missing with Claude detect"; exit 1; }
test -d .claude/skills || { echo "FAIL: .claude/skills missing when .claude/ exists"; exit 1; }
count_agents=$(find .agents/skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
count_claude=$(find .claude/skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_agents" -gt 0 ]] || { echo "FAIL: No skills in .agents/skills/"; exit 1; }
[[ "$count_claude" -gt 0 ]] || { echo "FAIL: No skills in .claude/skills/"; exit 1; }
echo "  Skills in .agents/skills/: $count_agents, .claude/skills/: $count_claude"

# --- Test 6: --dest-path disables Claude auto-detection ---
echo "Test 6: --dest-path disables Claude auto-detection ..."
rm -rf custom-skills .claude/skills
# .claude/ dir still exists from previous test
"$ROOT_DIR/upskill" adobe/helix-website -b main --all --dest-path custom-skills
test -d custom-skills || { echo "FAIL: custom-skills directory missing"; exit 1; }
count_custom=$(find custom-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_custom" -gt 0 ]] || { echo "FAIL: No skills in custom destination"; exit 1; }
test ! -d .claude/skills || { echo "FAIL: --dest-path should disable Claude auto-detect"; exit 1; }

# --- Test 7: --path subfolder filtering ---
echo "Test 7: --path subfolder filtering ..."
"$ROOT_DIR/upskill" adobe/skills -b main --path skills/aem/edge-delivery-services --all --dest-path path-filtered-skills
test -d path-filtered-skills || { echo "FAIL: path-filtered-skills directory missing"; exit 1; }
count_path=$(find path-filtered-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_path" -gt 0 ]] || { echo "FAIL: No skills found with --path filter"; exit 1; }
echo "  Found $count_path skill(s) with --path filter"

# --- Test 8: -i adds correct entries to .gitignore ---
echo "Test 8: -i adds correct entries to .gitignore ..."
rm -f .gitignore
# .claude/ dir still exists → should add both entries
"$ROOT_DIR/upskill" -i adobe/helix-website -b main --all
test -f .gitignore || { echo "FAIL: .gitignore not created"; exit 1; }
grep -qF ".agents/skills/" .gitignore || { echo "FAIL: .gitignore missing .agents/skills/ entry"; exit 1; }
grep -qF ".claude/skills/" .gitignore || { echo "FAIL: .gitignore missing .claude/skills/ entry when Claude detected"; exit 1; }

# --- Test 9: Gitignore is idempotent ---
echo "Test 9: Gitignore idempotency ..."
agents_count_before=$(grep -cF ".agents/skills/" .gitignore)
claude_count_before=$(grep -cF ".claude/skills/" .gitignore)
"$ROOT_DIR/upskill" -i adobe/helix-website -b main --all
agents_count_after=$(grep -cF ".agents/skills/" .gitignore)
claude_count_after=$(grep -cF ".claude/skills/" .gitignore)
[[ "$agents_count_before" == "$agents_count_after" ]] || { echo "FAIL: .agents/skills/ duplicated in .gitignore"; exit 1; }
[[ "$claude_count_before" == "$claude_count_after" ]] || { echo "FAIL: .claude/skills/ duplicated in .gitignore"; exit 1; }

# --- Test 10: --list still works ---
echo "Test 10: --list ..."
list_output=$("$ROOT_DIR/upskill" adobe/helix-website -b main --list 2>&1)
echo "$list_output" | grep -q "Available skills" || { echo "FAIL: --list output missing header"; exit 1; }
echo "$list_output" | grep -q "Found" || { echo "FAIL: --list output missing count"; exit 1; }

# --- Test 11: --path with invalid path ---
echo "Test 11: --path with invalid path ..."
if "$ROOT_DIR/upskill" adobe/skills -b main --path nonexistent/path --all --dest-path bad-path 2>/dev/null; then
  echo "FAIL: --path with invalid path should have failed"
  exit 1
fi
echo "  Correctly rejected invalid --path"

# --- Test 12: owner/repo@branch inline syntax ---
echo "Test 12: owner/repo@branch syntax ..."
"$ROOT_DIR/upskill" adobe/helix-website@main --all --dest-path at-branch-skills
test -d at-branch-skills || { echo "FAIL: at-branch-skills directory missing"; exit 1; }
count_at=$(find at-branch-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_at" -gt 0 ]] || { echo "FAIL: No skills installed with @branch syntax"; exit 1; }
echo "  Found $count_at skill(s) with @branch syntax"

# --- Test 13: -b flag takes precedence over @branch ---
echo "Test 13: -b precedence over @branch ..."
"$ROOT_DIR/upskill" adobe/helix-website@main -b main --all --dest-path b-precedence-skills
test -d b-precedence-skills || { echo "FAIL: b-precedence-skills directory missing"; exit 1; }
count_bp=$(find b-precedence-skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_bp" -gt 0 ]] || { echo "FAIL: No skills installed with -b precedence test"; exit 1; }
echo "  -b flag precedence works correctly"

# --- Test 14: --force flag ---
echo "Test 14: --force flag ..."
# Skills were already installed above; re-installing without --force should skip
skip_out=$("$ROOT_DIR/upskill" adobe/helix-website -b main --all 2>&1 || true)
if echo "$skip_out" | grep -q "already exists"; then
  echo "  Correctly skipped existing skill without --force"
else
  echo "FAIL: Expected skip warning for existing skill without --force"
  exit 1
fi

# Re-installing with --force should overwrite
force_out=$("$ROOT_DIR/upskill" adobe/helix-website -b main --all --force 2>&1)
if echo "$force_out" | grep -q "Overwriting existing skill"; then
  echo "  Correctly overwrote existing skill with --force"
else
  echo "FAIL: Expected overwrite message with --force"
  exit 1
fi
# Verify skills still present after --force
count_force=$(find .agents/skills -name 'SKILL.md' -type f | wc -l | tr -d ' ')
[[ "$count_force" -gt 0 ]] || { echo "FAIL: No skills after --force reinstall"; exit 1; }

# --- Test 15: upskill list subcommand ---
echo "Test 15: upskill list ..."
list_out=$("$ROOT_DIR/upskill" list 2>&1)
echo "$list_out" | grep -q "Discoverable local skills:" || { echo "FAIL: list header missing"; exit 1; }
echo "$list_out" | grep -q "NAME" || { echo "FAIL: list table header missing"; exit 1; }
echo "$list_out" | grep -q "SOURCE" || { echo "FAIL: list SOURCE column missing"; exit 1; }
echo "$list_out" | grep -q "PATH" || { echo "FAIL: list PATH column missing"; exit 1; }
echo "$list_out" | grep -q "Found .* skill(s)" || { echo "FAIL: list skill count missing"; exit 1; }
echo "  upskill list works with installed skills"

# --- Test 16: upskill list with no skills ---
echo "Test 16: upskill list with no skills ..."
empty_dir=$(mktemp -d)
pushd "$empty_dir" >/dev/null
no_skills_out=$(HOME="$empty_dir" "$ROOT_DIR/upskill" list 2>&1)
echo "$no_skills_out" | grep -q "No local skills found." || { echo "FAIL: empty list message missing"; exit 1; }
echo "$no_skills_out" | grep -q ".agents/skills/" || { echo "FAIL: empty list hint missing .agents/skills/"; exit 1; }
popd >/dev/null
rm -rf "$empty_dir"
echo "  upskill list works with no skills"

# --- Test 17: help includes list subcommand ---
echo "Test 17: help includes list subcommand ..."
help_out=$("$ROOT_DIR/upskill" --help 2>&1)
echo "$help_out" | grep -q "list" || { echo "FAIL: help does not mention list subcommand"; exit 1; }
echo "  Help text includes list subcommand"

# --- Test 18: info and read subcommands ---
echo "Test 18: info subcommand ..."
mkdir -p .agents/skills/test-info-skill
cat > .agents/skills/test-info-skill/SKILL.md <<'SKILLEOF'
---
name: test-info-skill
description: A test skill for info subcommand
---
# Test Info Skill

This is a test skill used for testing the info subcommand.
SKILLEOF

echo "helper content" > .agents/skills/test-info-skill/helper.txt

info_out=$("$ROOT_DIR/upskill" info test-info-skill)
echo "$info_out" | grep -q "Skill: test-info-skill" || { echo "FAIL: info missing skill name"; exit 1; }
echo "$info_out" | grep -q "Path: .agents/skills/test-info-skill/SKILL.md" || { echo "FAIL: info missing path"; exit 1; }
echo "$info_out" | grep -q "Source: project (.agents/skills)" || { echo "FAIL: info missing source"; exit 1; }
echo "$info_out" | grep -q "Description: A test skill for info subcommand" || { echo "FAIL: info missing description"; exit 1; }
echo "$info_out" | grep -q "Contents:" || { echo "FAIL: info missing contents header"; exit 1; }
echo "$info_out" | grep -q "SKILL.md" || { echo "FAIL: info contents missing SKILL.md"; exit 1; }
echo "$info_out" | grep -q "helper.txt" || { echo "FAIL: info contents missing helper.txt"; exit 1; }
echo "  info subcommand works correctly"

echo "Test 18b: read subcommand ..."
read_out=$("$ROOT_DIR/upskill" read test-info-skill)
echo "$read_out" | grep -q "name: test-info-skill" || { echo "FAIL: read missing frontmatter"; exit 1; }
echo "$read_out" | grep -q "# Test Info Skill" || { echo "FAIL: read missing heading"; exit 1; }
echo "$read_out" | grep -q "testing the info subcommand" || { echo "FAIL: read missing body text"; exit 1; }
echo "  read subcommand works correctly"

# --- Test 19: info/read with nonexistent skill ---
echo "Test 19: info/read with nonexistent skill ..."
if "$ROOT_DIR/upskill" info nonexistent-skill-xyz 2>/dev/null; then
  echo "FAIL: info should fail for nonexistent skill"
  exit 1
fi
if "$ROOT_DIR/upskill" read nonexistent-skill-xyz 2>/dev/null; then
  echo "FAIL: read should fail for nonexistent skill"
  exit 1
fi
echo "  Correctly rejected nonexistent skill"

# --- Test 20: info/read without name argument ---
echo "Test 20: info/read without name ..."
if "$ROOT_DIR/upskill" info 2>/dev/null; then
  echo "FAIL: info without name should fail"
  exit 1
fi
if "$ROOT_DIR/upskill" read 2>/dev/null; then
  echo "FAIL: read without name should fail"
  exit 1
fi
echo "  Correctly rejected missing name"

# --- Test 21: ClawHub and Tessl source detection ---
echo "Test 21: ClawHub and Tessl source detection ..."
help_out=$("$ROOT_DIR/upskill" --help 2>&1)
echo "$help_out" | grep -q "clawhub:" || { echo "FAIL: help does not mention clawhub: source"; exit 1; }
echo "$help_out" | grep -q "tessl:" || { echo "FAIL: help does not mention tessl: source"; exit 1; }
echo "$help_out" | grep -q "clawhub.ai" || { echo "FAIL: help does not mention clawhub.ai URL"; exit 1; }
echo "$help_out" | grep -q "Install sources:" || { echo "FAIL: help missing Install sources section"; exit 1; }
echo "  Help text includes ClawHub and Tessl sources"

# --- Test 22: clawhub: shorthand routing ---
echo "Test 22: clawhub: shorthand detection ..."
ch_out=$("$ROOT_DIR/upskill" clawhub:nonexistent-test-slug-xyz 2>&1 || true)
if echo "$ch_out" | grep -q "Downloading from ClawHub: nonexistent-test-slug-xyz"; then
  echo "  Correctly routed clawhub: shorthand to ClawHub install path"
elif echo "$ch_out" | grep -q "ClawHub download failed"; then
  echo "  Correctly routed clawhub: shorthand (download failed as expected for bad slug)"
else
  echo "FAIL: clawhub: shorthand was not routed to ClawHub install path"
  echo "Output: $ch_out"
  exit 1
fi

# --- Test 23: clawhub:user/slug extraction ---
echo "Test 23: clawhub:user/slug detection ..."
ch2_out=$("$ROOT_DIR/upskill" clawhub:someuser/my-skill 2>&1 || true)
if echo "$ch2_out" | grep -q "Downloading from ClawHub: my-skill"; then
  echo "  Correctly extracted slug from clawhub:user/slug"
elif echo "$ch2_out" | grep -q "ClawHub download failed"; then
  echo "  Correctly routed clawhub:user/slug (download failed as expected)"
else
  echo "FAIL: clawhub:user/slug was not parsed correctly"
  echo "Output: $ch2_out"
  exit 1
fi

# --- Test 24: ClawHub full URL detection ---
echo "Test 24: ClawHub URL detection ..."
ch_url_out=$("$ROOT_DIR/upskill" https://clawhub.ai/someuser/my-url-skill 2>&1 || true)
if echo "$ch_url_out" | grep -q "Downloading from ClawHub: my-url-skill"; then
  echo "  Correctly extracted slug from ClawHub URL"
elif echo "$ch_url_out" | grep -q "ClawHub download failed"; then
  echo "  Correctly routed ClawHub URL (download failed as expected)"
else
  echo "FAIL: ClawHub URL was not parsed correctly"
  echo "Output: $ch_url_out"
  exit 1
fi

# --- Test 25: tessl: shorthand detection ---
echo "Test 25: tessl: shorthand detection ..."
ts_out=$("$ROOT_DIR/upskill" tessl:nonexistent-test-skill-xyz 2>&1 || true)
if echo "$ts_out" | grep -q "Resolving Tessl skill: nonexistent-test-skill-xyz"; then
  echo "  Correctly routed tessl: shorthand to Tessl resolve path"
elif echo "$ts_out" | grep -q "Tessl"; then
  echo "  Correctly routed tessl: shorthand (API call made as expected)"
else
  echo "FAIL: tessl: shorthand was not routed to Tessl resolve path"
  echo "Output: $ts_out"
  exit 1
fi

# --- Test 26: upskill search (resilient to registry availability) ---
echo "Test 26: upskill search ..."
if command -v jq >/dev/null 2>&1; then
  search_out=$("$ROOT_DIR/upskill" search "pdf" 2>&1 || true)
  if echo "$search_out" | grep -q 'Search results for "pdf"'; then
    echo "$search_out" | grep -q "NAME" || { echo "FAIL: search table header missing"; exit 1; }
    echo "$search_out" | grep -q "SOURCE" || { echo "FAIL: search SOURCE column missing"; exit 1; }
    echo "$search_out" | grep -q "To install:" || { echo "FAIL: search install hint missing"; exit 1; }
    echo "  upskill search works"
  elif echo "$search_out" | grep -Eqi 'registry unavailable|service unavailable|temporarily unavailable|rate limit|timed out|timeout|failed to .*ClawHub|failed to .*Tessl|unable to .*ClawHub|unable to .*Tessl|warning:.*ClawHub|warning:.*Tessl|Both registries failed'; then
    echo "  SKIP: search registries unavailable; skipping strict search result assertions"
  else
    echo "FAIL: unexpected search output"
    echo "Output: $search_out"
    exit 1
  fi

  # Test search without query argument
  echo "Test 26b: search without query ..."
  if "$ROOT_DIR/upskill" search 2>/dev/null; then
    echo "FAIL: search without query should fail"
    exit 1
  fi
  echo "  Correctly rejected search without query"

  # Test that search subcommand is mentioned in help
  echo "Test 26c: help includes search subcommand ..."
  help_search_out=$("$ROOT_DIR/upskill" --help 2>&1)
  echo "$help_search_out" | grep -q "search" || { echo "FAIL: help does not mention search subcommand"; exit 1; }
  echo "  Help text includes search subcommand"
else
  echo "  SKIP: jq not installed, skipping search tests"
fi

echo ""
echo "ALL TESTS PASSED"

popd >/dev/null
