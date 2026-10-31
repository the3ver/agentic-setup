#!/usr/bin/env bash
# Smoke-Test fuer inventory.sh: baut ein kleines Wegwerf-Repo mit bekannten Befunden und prueft die Ausgabe.
# Aufruf: bash tests/smoke.sh   (Exit 0 = alle Pruefungen gruen)
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
printf '# Projekt\n\nVersion 1.2.3, siehe left-pad im Changelog.\n' > README.md
printf '@AGENTS.md\n' > CLAUDE.md
printf '# Agenten\n' > AGENTS.md
printf 'node_modules/\n' > .gitignore
git add -A && git commit -q -m "feat: start"
git switch -q -c liegengeblieben && git commit -q --allow-empty -m "fix(test): flaky test stabil" && git switch -q main

out=$(bash "$inv" . 2>&1)
status=$?
fail=0
expect() { grep -qE "$1" <<<"$out" || { echo "FEHLT: $1"; fail=1; }; }

[ $status -eq 0 ] || { echo "Exit $status statt 0"; fail=1; }
expect 'package-lock\.json: 1\.2\.0  ABWEICHUNG von 1\.2\.3'
expect 'Abhängigkeiten ohne Fundstelle im Code: left-pad$'
expect 'ungemergt: liegengeblieben'
expect 'Feste Wartezeiten in Tests.*: 1'
expect 'JS-Module: 1 mit DOM-Zugriff, 1 ohne: +main\.js'
expect 'importiert AGENTS\.md'
expect 'node_modules/ ungeschützt'
expect 'keine \.gitattributes'
[ "$(grep -c '^- AGENTS\.md' <<<"$out")" -eq 0 ] || { echo "AGENTS.md doppelt gezählt"; fail=1; }

if [ $fail -eq 0 ]; then echo "SMOKE OK"; else echo "--- Ausgabe ---"; echo "$out"; fi
exit $fail
