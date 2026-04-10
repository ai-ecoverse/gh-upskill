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

echo ""
echo "ALL TESTS PASSED"

popd >/dev/null
