#!/usr/bin/env bash
# Smoke test for inventory.sh: builds a small throwaway repo with known history and pipeline facts and checks the output.
# The fixture is deliberately neither Java nor JavaScript: the script must stay stack-independent.
# Usage: bash tests/smoke.sh   (exit 0 = all checks green)
set -uo pipefail
inv="$(cd "$(dirname "$0")/.." && pwd)/skills/analyse-project-setup/inventory.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT

cd "$repo"
git init -q -b main
git config user.email test@example.com
git config user.name test
commit() { git add -A && git commit -q -m "$1"; }

mkdir -p app tests
printf '[project]\nname = "fixture"\nversion = "1.2.3"\n' > pyproject.toml
printf 'def parse(x):\n    return x\n' > app/parser.py
printf 'def test_parse():\n    assert True\n' > tests/test_parser.py
printf '@AGENTS.md\n' > CLAUDE.md
printf '# Agents\n' > AGENTS.md
printf 'build/\n' > .gitignore
printf 'Version 1.2.3\n' > README.md
commit "feat: parser"
printf 'def parse(x):\n    return x.strip()\n' > app/parser.py
commit "fix(parser): strip input"
printf 'def parse(x):\n    return x.strip().lower()\n' > app/parser.py
commit "fix(parser): normalise case"
printf 'def test_parse():\n    assert parse(" A ") == "a"\n' > tests/test_parser.py
commit "test: make flaky parser test deterministic"
printf 'x' > notes.txt
commit "chore: fixed wording in notes"
git tag v1.2.3
git switch -q -c stranded && git commit -q --allow-empty -m "fix: stranded repair" && git switch -q main
mkdir -p build && printf 'artefact' > build/out.bin

out=$(bash "$inv" . 2>&1)
status=$?
fail=0
expect() { grep -qE -- "$1" <<<"$out" || { echo "MISSING: $1"; fail=1; }; }
absent() { ! grep -qE -- "$1" <<<"$out" || { echo "UNEXPECTED: $1"; fail=1; }; }

[ $status -eq 0 ] || { echo "exit $status instead of 0"; fail=1; }
expect 'Repair commits: 3 of 5'
expect 'make flaky parser test deterministic'
absent 'fixed wording'
expect '^- 2 app/parser\.py'
expect 'unmerged: stranded'
expect 'Latest tag: v1\.2\.3'
expect '^  - (README\.md|pyproject\.toml)'
expect '\| py \| 2 \|'
expect 'imports AGENTS\.md'
expect '^- build/ .*\(unprotected\)'
expect 'no CI configuration found'
expect 'no \.gitattributes'
absent 'awk: '
[ "$(grep -c '^- AGENTS\.md' <<<"$out")" -eq 0 ] || { echo "AGENTS.md counted twice"; fail=1; }

if [ $fail -eq 0 ]; then echo "SMOKE OK"; else echo "--- output ---"; echo "$out"; fi
exit $fail
