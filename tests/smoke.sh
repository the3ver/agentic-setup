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
printf 'build/\nconfig.json\n.agents/\n' > .gitignore
printf '# Fixture\n\nVersion 1.2.3\n\n```bash\n# run all tests\npython -m pytest -q\n```\n' > README.md
# Manifest and lockfile; the lockfile's own version lags far behind (outside the 1.2 family)
printf '{"name": "fixture", "version": "1.2.2"}\n' > package.json
printf '{"name": "fixture", "version": "0.1.0", "packages": {"": {"version": "0.1.0"}}}\n' > package-lock.json
printf 'export default { retries: 2 };\n' > playwright.config.js
printf '@echo off\r\necho build\r\n' > build.bat
printf 'line one\r\nline two\n' > mixed.txt
commit "feat: parser"
printf 'def parse(x):\n    return x.strip()\n' > app/parser.py
commit "fix(parser): strip input"
printf 'def parse(x):\n    return x.strip().lower()\n' > app/parser.py
# A version-only touch inside a repair commit must not count as a hotspot
printf '{"name": "fixture", "version": "1.2.3"}\n' > package.json
commit "fix(parser): normalise case"
printf 'def test_parse():\n    assert parse(" A ") == "a"\n' > tests/test_parser.py
commit "test: make flaky parser test deterministic"
printf 'x' > notes.txt
commit "chore: fixed wording in notes"
# A repair hidden in a feature commit, together with a binary test artefact
printf 'def parse(x):\n    return x.strip().lower() or None\n' > app/parser.py
printf '\x89PNG\x00\x01' > shot.png
commit "feat(parser): fix race finish bug, add empty check"
git tag v1.2.3
# Version moves past the tag in the manifest only; README keeps the old value
printf '[project]\nname = "fixture"\nversion = "1.2.4"\n' > pyproject.toml
printf '{"name": "fixture", "version": "1.2.4"}\n' > package.json
commit "chore(release): 1.2.4"
git switch -q -c stranded && git commit -q --allow-empty -m "fix: stranded repair" && git switch -q main
mkdir -p build && printf 'artefact' > build/out.bin
printf '{"iban": "x"}' > config.json
mkdir -p .agents && printf '# local agent notes\n' > .agents/AGENTS.md

out=$(bash "$inv" . 2>&1)
status=$?
fail=0
expect() { grep -qE -- "$1" <<<"$out" || { echo "MISSING: $1"; fail=1; }; }
absent() { ! grep -qE -- "$1" <<<"$out" || { echo "UNEXPECTED: $1"; fail=1; }; }

[ $status -eq 0 ] || { echo "exit $status instead of 0"; fail=1; }
expect 'Repair commits: 4 of 7'
expect 'make flaky parser test deterministic'
expect 'fix race finish bug.*\[embedded repair\]'
absent 'fixed wording'
expect '^- 3 app/parser\.py'
absent '^- [0-9]+ (package\.json|shot\.png)'
expect 'Binary files changed by repair commits: 1'
expect 'unmerged: stranded'
expect 'Latest tag: v1\.2\.3-1-.*\(HEAD is past the tag\)'
expect 'Current version: 1\.2\.4, declared in: .*pyproject\.toml'
expect 'Manifest versions: .*package\.json 1\.2\.4.*package-lock\.json 0\.1\.0'
expect 'MISMATCH: manifests and lockfiles disagree'
expect 'MISMATCH: other versions of the 1\.2 family'
expect '^  - 1\.2\.3 in README\.md'
expect 'mixed: mixed\.txt'
expect 'script: build\.bat'
expect 'documented in README\.md: python -m pytest -q'
absent 'documented in README\.md: #'
expect 'playwright\.config\.js: .*retries: 2'
expect '\.agents/ is git-ignored'
expect '^- config\.json \(no deny rule\)'
expect 'Commit-time hooks:'
expect '^- none'
expect '\| py \| 2 \|'
absent '\| gitignore \|'
expect 'imports AGENTS\.md'
expect '^- build/ .*\(unprotected\)'
expect 'no CI configuration found'
expect 'no \.gitattributes'
absent 'awk: '
[ "$(grep -c '^- AGENTS\.md' <<<"$out")" -eq 0 ] || { echo "AGENTS.md counted twice"; fail=1; }

# A fresh repo (one commit, no tags, no repairs) must still produce a complete inventory
fresh=$(mktemp -d)
trap 'rm -rf "$repo" "$fresh"' EXIT
(cd "$fresh" && git init -q -b main && git config user.email t@example.com && git config user.name t \
  && printf 'fn main() {}\n' > main.rs && printf '[package]\nname = "x"\n' > Cargo.toml \
  && git add -A && git commit -q -m "initial commit")
out=$(bash "$inv" "$fresh" 2>&1)
status=$?
[ $status -eq 0 ] || { echo "fresh repo: exit $status instead of 0"; fail=1; }
expect 'Repair commits: 0 of 1'
expect 'Latest tag: none'
expect 'no declared version found'
expect '\| rs \| 1 \|'
expect 'Cargo\.toml'
expect '## Noise sources'
absent 'awk: |fatal:'

if [ $fail -eq 0 ]; then echo "SMOKE OK"; else echo "--- output ---"; echo "$out"; fi
exit $fail
