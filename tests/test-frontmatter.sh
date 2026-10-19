#!/usr/bin/env bash
# Test frontmatter field extraction for YAML scalar styles.
# Covers: folded (>), literal (|), >-, |+, quoted with # and :,
# and multi-line plain continuation.
# Each case fails before the fix (ai-ecoverse/gh-upskill#28).
#
# Expected values were generated with PyYAML 6.0 (python3 -c yaml.safe_load)
# and verified byte-for-byte. Trailing newlines from clip/keep chomping are
# stripped by bash $(), matching PyYAML's output through the same capture.
set -Eeo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
FIXTURES="$ROOT_DIR/tests/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    printf '    expected: %s\n' "$expected"
    printf '    actual:   %s\n' "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Source extract_frontmatter_field by loading the script with main() stubbed out
eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ROOT_DIR/upskill")"

echo "=== Frontmatter field extraction tests ==="

# --- 1. Folded scalar (>) ---
echo "Test 1: Folded scalar (>)"
actual=$(extract_frontmatter_field "$FIXTURES/folded-skill/SKILL.md" "description")
expected="Stop and check this skill before finishing any reply to a question about how to use Claude or a Claude product — it includes the canonical list of Claude products and features."
assert_eq "description: >" "$expected" "$actual"
actual_name=$(extract_frontmatter_field "$FIXTURES/folded-skill/SKILL.md" "name")
assert_eq "name (plain alongside >)" "folded-skill" "$actual_name"

# --- 2. Literal scalar (|) ---
echo "Test 2: Literal scalar (|)"
actual=$(extract_frontmatter_field "$FIXTURES/literal-skill/SKILL.md" "description")
expected=$'Line one of the description.\nLine two of the description.\nLine three of the description.'
assert_eq "description: |" "$expected" "$actual"

# --- 3. Folded strip (>-) ---
echo "Test 3: Folded strip (>-)"
actual=$(extract_frontmatter_field "$FIXTURES/strip-skill/SKILL.md" "description")
expected="Hello world this is a folded description with strip chomp"
assert_eq "description: >-" "$expected" "$actual"

# --- 4. Literal keep (|+) ---
echo "Test 4: Literal keep (|+)"
actual=$(extract_frontmatter_field "$FIXTURES/keep-skill/SKILL.md" "description")
# |+ keeps trailing newlines, but $() strips them – so value matches |
expected=$'Line one.\nLine two.'
assert_eq "description: |+" "$expected" "$actual"

# --- 5. Quoted values with # and : ---
echo "Test 5: Quoted values with special characters"
actual_name=$(extract_frontmatter_field "$FIXTURES/quoted-skill/SKILL.md" "name")
assert_eq "single-quoted name with :" "quoted: skill" "$actual_name"
actual_desc=$(extract_frontmatter_field "$FIXTURES/quoted-skill/SKILL.md" "description")
assert_eq "single-quoted desc with # and :" "has a # hash and a: colon inside" "$actual_desc"

# --- 6. Multi-line plain scalar ---
echo "Test 6: Multi-line plain scalar"
actual=$(extract_frontmatter_field "$FIXTURES/plain-multi-skill/SKILL.md" "description")
expected="This is a long description that continues on multiple lines"
assert_eq "multi-line plain continuation" "$expected" "$actual"

# --- 7. CLI info output (end-to-end) ---
echo "Test 7: CLI info shows full descriptions"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.agents/skills"
cp -r "$FIXTURES/folded-skill" "$TMP/.agents/skills/"
cp -r "$FIXTURES/quoted-skill" "$TMP/.agents/skills/"

pushd "$TMP" >/dev/null
info_out=$("$ROOT_DIR/upskill" info folded-skill 2>&1 || true)
if echo "$info_out" | grep -qF "Stop and check"; then
  assert_eq "info shows folded description" "yes" "yes"
else
  assert_eq "info shows folded description (not '>')" "yes" "no"
fi

info_out=$("$ROOT_DIR/upskill" info quoted-skill 2>&1 || true)
if echo "$info_out" | grep -qF "has a # hash"; then
  assert_eq "info shows quoted description" "yes" "yes"
else
  assert_eq "info shows quoted description" "yes" "no"
fi
popd >/dev/null

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

# --- 8. PyYAML cross-check (optional, when python3 + PyYAML available) ---
if python3 -c 'import yaml' 2>/dev/null; then
  echo ""
  echo "Test 8: PyYAML byte-for-byte cross-check"
  yaml_fail=0
  for d in "$FIXTURES"/*/; do
    skill=$(basename "$d")
    path="$d/SKILL.md"
    [[ -f "$path" ]] || continue
    for field in name description; do
      expected=$(python3 -c "
import yaml, sys
with open('$path') as f:
    content = f.read()
parts = content.split('---', 2)
fm = yaml.safe_load(parts[1])
val = fm.get('$field', '')
if val is None: val = ''
val = str(val).rstrip('\\n')  # match bash \$() stripping
sys.stdout.write(val)
")
      actual=$(extract_frontmatter_field "$path" "$field")
      if [[ "$actual" != "$expected" ]]; then
        echo "  MISMATCH: $skill/$field"
        printf '    expected hex: %s\n' "$(printf '%s' "$expected" | xxd -p | tr -d '\n')"
        printf '    actual hex:   %s\n' "$(printf '%s' "$actual" | xxd -p | tr -d '\n')"
        yaml_fail=1
      fi
    done
  done
  if [[ $yaml_fail -eq 0 ]]; then
    echo "  All fields match PyYAML byte-for-byte"
  else
    echo "  FAIL: some fields diverge from PyYAML"
    exit 1
  fi
else
  echo "SKIP: python3/PyYAML not available for cross-check"
fi

echo "ALL FRONTMATTER TESTS PASSED"
