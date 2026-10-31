#!/usr/bin/env bash
# Smoke test for inventory.sh: builds a small throwaway repo with known findings and checks the output.
# Usage: bash tests/smoke.sh   (exit 0 = all checks green)
set -uo pipefail
inv="$(cd "$(dirname "$0")/.." && pwd)/skills/analyse-project-setup/inventory.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT

cd "$repo"
git init -q -b main
git config user.email test@example.com
git config user.name test
mkdir -p src tests node_modules/x
cat > package.json <<'EOF'
{
  "name": "fixture",
  "version": "1.2.3",
  "scripts": { "test": "playwright test" },
  "devDependencies": {
    "@playwright/test": "^1.0.0",
    "left-pad": "^1.0.0"
  }
}
EOF
printf '{ "version": "1.2.0" }\n' > package-lock.json
printf 'import { helper } from "./util.js";\nexport const a = helper(1);\n' > src/main.js
printf 'export function helper(x) { return document.title + x; }\n' > src/util.js
printf 'test("a", async ({ page }) => { await page.waitForTimeout(100); });\n' > tests/a.spec.js
printf '# Project\n\nVersion 1.2.3, see left-pad in the changelog.\n' > README.md
printf '@AGENTS.md\n' > CLAUDE.md
printf '# Agents\n' > AGENTS.md
printf 'node_modules/\n' > .gitignore
git add -A && git commit -q -m "feat: start"
git switch -q -c stranded && git commit -q --allow-empty -m "fix(test): stabilise flaky test" && git switch -q main

out=$(bash "$inv" . 2>&1)
status=$?
fail=0
expect() { grep -qE "$1" <<<"$out" || { echo "MISSING: $1"; fail=1; }; }

[ $status -eq 0 ] || { echo "exit $status instead of 0"; fail=1; }
expect 'package-lock\.json: 1\.2\.0  MISMATCH with 1\.2\.3'
expect 'Dependencies not found in code: left-pad$'
expect 'unmerged: stranded'
expect 'Fixed waits in tests.*: 1'
expect 'JS modules: 1 with DOM access, 1 without: +main\.js'
expect 'imports AGENTS\.md'
expect 'node_modules/ unprotected'
expect 'no \.gitattributes'
[ "$(grep -c '^- AGENTS\.md' <<<"$out")" -eq 0 ] || { echo "AGENTS.md counted twice"; fail=1; }

if [ $fail -eq 0 ]; then echo "SMOKE OK"; else echo "--- output ---"; echo "$out"; fi
exit $fail
