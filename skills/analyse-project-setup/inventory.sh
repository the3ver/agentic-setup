#!/usr/bin/env bash
# Deterministische Bestandsaufnahme eines Repos fuer analyse-project-setup.
# Aufruf: bash inventory.sh [repo-pfad]. Ausgabe: kompaktes Markdown auf stdout.
set -u
cd "${1:-.}" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Kein Git-Repo: $(pwd)"; exit 1; }

files() { git ls-files; }
py=$(command -v python || command -v python3)
has() { [ -e "$1" ] && echo "ja" || echo "-"; }
grepf() { grep -l -E "$1" "${@:2}" 2>/dev/null | head -1; }

echo "# Inventar $(basename "$(pwd)")"
echo
echo "## Git"
echo "- Branch: $(git branch --show-current), Commits: $(git rev-list --count HEAD 2>/dev/null)"
echo "- Uncommittet: $(git status --porcelain | wc -l) Dateien"
total=$(git log --format=%s -50 | wc -l)
conv=$(git log --format=%s -50 | grep -cE '^(feat|fix|refactor|docs|test|chore|style|perf|build|ci)(\(.+\))?!?:')
echo "- Conventional Commits (letzte 50): $conv/$total"
echo "- Remote: $(git remote get-url origin 2>/dev/null || echo -)"
# Pannen-Kandidaten fuer Schritt 1: Commits, die Flaky-Tests, Reverts oder Testreparaturen nennen
git log --format='%h %s' -300 | grep -iE 'flaky|wackel|revert|fix\(test|deterministisch|vergessen|forgot' | head -8 | sed 's/^/  - Panne? /'
# Liegengebliebene Arbeit: Branches, die nicht im aktuellen Branch gelandet sind, und zusaetzliche Worktrees
git for-each-ref --no-merged HEAD --format='%(refname:short) %(committerdate:short) %(subject)' refs/heads | head -8 | sed 's/^/  - ungemergt: /'
git worktree list | tail -n +2 | head -5 | sed 's/^/  - Worktree: /'
# Arbeitsbaum zaehlt: dort lesen und schreiben Agenten (Index ist bei text=auto immer LF)
eol=$(git ls-files --eol | awk '{print $2}' | sed 's/^w\///' | grep -vE '^(-text|none|)$' | sort | uniq -c | tr -s ' ' | tr '\n' ',')
echo "- Zeilenenden im Arbeitsbaum:${eol%,}"

echo
echo "## Stack"
for f in build.gradle build.gradle.kts settings.gradle pom.xml package.json pnpm-lock.yaml yarn.lock \
         pyproject.toml requirements.txt Cargo.toml go.mod tsconfig.json vite.config.ts vite.config.js; do
  [ -e "$f" ] && echo "- $f"
done
ls *.csproj *.sln 2>/dev/null | sed 's/^/- /'
if [ -e package.json ]; then
  if grep -q '"type": *"module"' package.json; then
    echo "- ES-Module (type: module)"
  elif files | grep -E '\.html$' | tr '\n' '\0' | xargs -0 grep -lq '<script[^>]*type="module"' 2>/dev/null; then
    echo "- ES-Module im Browser (<script type=\"module\">)"
  fi
  if ! grep -qE '"build"\s*:' package.json && ! ls vite.config.* webpack.config.* rollup.config.* esbuild.* tsconfig.json >/dev/null 2>&1; then
    echo "- Kein Build-Schritt (kein build-Script, kein Bundler, kein tsconfig)"
  fi
fi
node_v=$(cat .nvmrc .node-version 2>/dev/null | head -1)
[ -z "$node_v" ] && [ -d .github/workflows ] && node_v=$(grep -hoE "node-version: *['\"]?[0-9.x]+" .github/workflows/* 2>/dev/null | head -1 | grep -oE '[0-9.x]+$')
[ -n "$node_v" ] && echo "- Node-Version (Projekt/CI): $node_v"
[ -e package.json ] && command -v node >/dev/null && echo "- Node lokal: $(node --version)"
java_v=$(grep -hoE "(languageVersion.*of\(|release = |java-version: *['\"]?)[0-9]+" build.gradle* .github/workflows/* 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')
[ -n "$java_v" ] && echo "- Java-Version(en): $java_v"

echo
echo "## Tests"
for f in playwright.config.* vitest.config.* jest.config.* pytest.ini; do [ -e "$f" ] && echo "- Konfiguration: $f"; done
[ -e package.json ] && grep -oE '"(vitest|jest|mocha|@playwright/test|node:test)"' package.json | sort -u | sed 's/^/- Framework: /'
grep -qiE 'junit|testng|spock' build.gradle* pom.xml 2>/dev/null && echo "- Framework: JUnit/TestNG (Build-Datei)"
grep -q pytest pyproject.toml 2>/dev/null && echo "- Framework: pytest"
testfiles=$(files | grep -iE '(^|/)(test|tests|__tests__|spec)/|[._-](test|spec)\.[a-z]+$|Test\.(java|kt)$')
if [ -n "$testfiles" ]; then
  cases=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE '^\s*(test|it)(\.only|\.skip)?\(|@(Test|ParameterizedTest)\b|^\s*def test_' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Testfälle (grob gezählt): ${cases:-?}"
  sleeps=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE 'waitForTimeout|Thread\.sleep|time\.sleep|setTimeout\(' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Feste Wartezeiten in Tests (waitForTimeout, sleep, setTimeout): ${sleeps:-0}"
  skips=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE '\.(skip|only)\(|@Disabled|@Ignore|pytest\.mark\.skip' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Übersprungene/fokussierte Tests: ${skips:-0}"
  # Strukturtests: Tests, die Quelltext lesen und gegen Regeln pruefen (Waechtertests)
  guards=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -lE "(readFileSync|readdirSync|Files\.(readString|walk|lines)|open\().*(src|main)|archunit|ArchRule" 2>/dev/null | tr '\n' ' ')
  echo "- Strukturtests (lesen Quelltext oder ArchUnit): ${guards:--}"
  grep -hoE '(retries|reporter|forbidOnly|workers): *[^,}]+' playwright.config.* 2>/dev/null | sort -u | sed 's/^/- Playwright /'
fi

echo
echo "## Code (versioniert)"
echo "| Endung | Dateien | Zeilen | davon Test-Dateien |"
echo "|---|---|---|---|"
for ext in java kt ts tsx js mjs vue py go rs cs; do
  list=$(files | grep -E "\.${ext}$" | grep -vE '(^|/)(node_modules|dist|build|vendor)/')
  [ -z "$list" ] && continue
  n=$(echo "$list" | wc -l)
  loc=$(echo "$list" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l)
  t=$(echo "$list" | grep -ciE '(^|/)(test|tests|__tests__|spec)/|[._-](test|spec)\.|Test\.|Tests\.')
  echo "| $ext | $n | $loc | $t |"
done
echo
echo "Größte Quelldateien:"
files | grep -E '\.(java|kt|ts|tsx|js|vue|py|go|rs|cs)$' | grep -viE 'test|spec|\.min\.' \
  | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null | grep -v ' total$' | sort -rn | head -5 | sed 's/^ */- /'

# JS: Module ohne DOM-Zugriff sind Kandidaten fuer schnelle Node-Unit- und Mutationstests
jsmods=$(files | grep -E '\.m?js$' | grep -viE '(^|/)(test|tests|spec|node_modules|dist)/|\.(spec|test|min|config)\.')
if [ -n "$jsmods" ]; then
  pure=""; npure=0; ndom=0
  for f in $jsmods; do
    if grep -qE '\b(document|window|navigator|localStorage)\.' "$f"; then ndom=$((ndom + 1))
    else npure=$((npure + 1)); pure="$pure $(basename "$f")"; fi
  done
  echo
  echo "JS-Module: $ndom mit DOM-Zugriff, $npure ohne:$(echo "$pure" | cut -c1-300)"
  echo "Meiste Imports:"
  for f in $jsmods; do echo "$(grep -cE '^\s*import ' "$f") $f"; done | sort -rn | head -3 | sed 's/^/- /'
fi

echo
echo "## Qualitätswerkzeuge (Konfiguration gefunden)"
buildfiles=$(ls build.gradle build.gradle.kts pom.xml package.json pyproject.toml 2>/dev/null)
check() { # name, regex in Build-Dateien, Datei-Globs
  local name=$1 rx=$2; shift 2
  local hit=""
  [ -n "$rx" ] && [ -n "$buildfiles" ] && hit=$(grepf "$rx" $buildfiles)
  for g in "$@"; do [ -z "$hit" ] && hit=$(ls -d $g 2>/dev/null | head -1); done
  echo "- $name: ${hit:--}"
}
check "Formatter" 'spotless|prettier|biome|ruff format|black|ktlint|google-java-format' \
      .prettierrc* biome.json
check "EditorConfig" '' .editorconfig
check "Linter" 'checkstyle|pmd|eslint|ruff|pylint|detekt|clippy' eslint.config.* .eslintrc* config/checkstyle
check "Compiler-Checks" 'errorprone|nullaway|"strict": *true|mypy|pyright' tsconfig.json
check "Architekturregeln" 'archunit|dependency-cruiser|import-linter|eslint-plugin-boundaries' .dependency-cruiser*
check "Mutation Testing" 'pitest|stryker|mutmut' stryker.conf*
check "Coverage" 'jacoco|kover|"c8"|"nyc"|--coverage|pytest-cov'
check "Semgrep" '' .semgrep* .semgrep.yml semgrep.yml
check "Toter Code / Deps" 'knip|depcheck|vulture|unused' knip.json
check "Git-Hooks" 'husky|lint-staged|lefthook' .husky .pre-commit-config.yaml lefthook.yml .githooks
check "Task-Runner" '' justfile Justfile Makefile Taskfile.yml
check "Datengenerierung" 'fabric-datagen|datagen|openapi-generator|codegen'

if [ -e package.json ]; then
  echo
  echo "package.json scripts:"
  # JSON echt parsen: sed-Bereiche scheitern an einzeiligen Objekten
  # Python unter Windows schreibt CRLF; das \r wuerde jeden Namensvergleich verfaelschen
  pkg() { "$py" -c "import json; d=json.load(open('package.json',encoding='utf-8')); $1" 2>/dev/null | tr -d '\r'; }
  scripts=$(pkg "[print(f'{k}: {v}') for k,v in d.get('scripts',{}).items()]")
  [ -n "$scripts" ] && sed 's/^/- /' <<<"$scripts"
  # Abhaengigkeiten, die weder importiert noch in einem npm-Script als CLI aufgerufen werden (Kandidaten)
  deps=$(pkg "[print(k) for s in ('dependencies','devDependencies') for k in d.get(s,{})]")
  code=$(files | grep -E '\.(m?js|cjs|ts|tsx|vue|svelte|html)$')
  unused=""
  for d in $deps; do
    echo "$code" | tr '\n' '\0' | xargs -0 grep -qE "(from|require\(|import\() *['\"]${d}['\"/]" 2>/dev/null && continue
    grep -qE "(^|[\" &;])${d##*/}( |\"|$)|${d#@}" <<<"$scripts" && continue
    [ "$d" = "@playwright/test" ] && grep -q playwright <<<"$scripts" && continue
    unused="$unused $d"
  done
  [ -n "$unused" ] && echo "- Abhängigkeiten ohne Fundstelle im Code:$unused"
fi

echo
echo "## CI / GitHub"
if [ -d .github/workflows ]; then
  for w in .github/workflows/*.y*ml; do
    trig=$(grep -A6 -E '^on:' "$w" | grep -oE '(push|pull_request|schedule|workflow_dispatch|release|tags)' | sort -u | tr '\n' ' ')
    runs=$(grep -E '^\s*run:' "$w" | sed -E 's/^\s*run:\s*//' | head -4 | tr '\n' ';')
    echo "- $(basename "$w") [$trig] run: ${runs:--}"
  done
  grep -l 'continue-on-error' .github/workflows/* 2>/dev/null | sed 's/^/- continue-on-error in: /'
  grep -l 'upload-sarif\|codeql' .github/workflows/* 2>/dev/null | sed 's/^/- Code Scanning in: /'
else
  echo "- keine Workflows"
fi
echo "- Dependabot: $(has .github/dependabot.yml), Renovate: $(ls renovate.json* .github/renovate.json* 2>/dev/null | head -1 | grep . || echo -), CODEOWNERS: $(has .github/CODEOWNERS)"

echo
echo "## Agenten-Konfiguration"
# Groesse in Bytes zaehlt fuer den Kontext, nicht die Zeilenzahl (~4 Bytes je Token)
size() { local b; b=$(wc -c < "$1"); echo "$(wc -l < "$1") Zeilen, $((b / 1024)) KB, ~$((b / 4)) Tokens"; }
seen=" "
for f in CLAUDE.md AGENTS.md GEMINI.md .agents/AGENTS.md .cursorrules .github/copilot-instructions.md .mcp.json; do
  [ -e "$f" ] || continue
  # Schon als Import gemessene Dateien nicht doppelt zaehlen
  [[ $seen == *" $f "* ]] && continue
  echo "- $f ($(size "$f"))"
  for imp in $(grep -oE '^@[^ ]+' "$f" | cut -c2-); do
    imp=${imp/#\~/$HOME}
    seen="$seen$imp "
    [ -e "$imp" ] && echo "  - importiert $imp ($(size "$imp"))" || echo "  - importiert $imp (fehlt)"
  done
done
for f in .claude/settings.json .claude/settings.local.json; do
  [ -e "$f" ] || continue
  echo "- $f: hooks=$(grep -c '"hooks"' "$f"), permissions=$(grep -c '"permissions"' "$f")"
  grep -oE '"(PreToolUse|PostToolUse|Stop|SubagentStop|UserPromptSubmit|SessionStart)"' "$f" | sort -u | sed 's/^/  - Hook-Event /'
done
[ -d .claude/skills ] && echo "- Projekt-Skills: $(ls .claude/skills | tr '\n' ' ')"
[ -d .claude/agents ] && echo "- Projekt-Agenten: $(ls .claude/agents | tr '\n' ' ')"
[ -d .claude/commands ] && echo "- Projekt-Commands: $(ls .claude/commands | tr '\n' ' ')"
src=$(git check-ignore -v .claude/settings.json 2>/dev/null | cut -f1)
[ -n "$src" ] && echo "- .claude/settings.json wäre git-ignoriert (Quelle: ${src%:*}), Hooks und Deny-Regeln gelten nur lokal$([ -e .claude/settings.json ] || echo '; Datei existiert noch nicht')"
denycount() { "$py" -c "import json,sys; print(len(json.load(open(sys.argv[1],encoding='utf-8')).get('permissions',{}).get('deny',[])))" "$1" 2>/dev/null || echo "?"; }
g=$HOME/.claude/settings.json
if [ -e "$g" ]; then
  ev=$(grep -oE '"(PreToolUse|PostToolUse|Stop|UserPromptSubmit|SessionStart)"' "$g" | sort -u | tr -d '"' | tr '\n' ' ')
  echo "- Global ~/.claude/settings.json: Hooks: ${ev:--}, Deny-Regeln: $(denycount "$g")"
fi
[ -e .claude/settings.json ] && echo "- Projekt-Deny-Regeln: $(denycount .claude/settings.json)"
# Skripte ausserhalb von Quell- und Testordnern, die Befehle ausfuehren (Agent-Bridges, Automatisierung)
for f in $(files | grep -E '\.(py|sh|mjs|js|ps1)$' | grep -vE '^(src|test|tests|docs|node_modules|gradle)/|(^|/)gradlew'); do
  grep -qE 'subprocess|child_process|os\.system|exec(Sync)?\(|eval\(|Invoke-Expression' "$f" && echo "- Achtung: $f führt Befehle aus"
done | head -8

echo
echo "## Versionsstellen"
semver='[0-9]+\.[0-9]+\.[0-9]+'
declared() { # Datei, Version laut Datei
  case $1 in
    gradle.properties) grep -m1 -E '^version *=' "$1" | grep -oE "$semver" ;;
    package.json|package-lock.json) grep -m1 '"version"' "$1" | grep -oE "$semver" ;;
    pyproject.toml|Cargo.toml) grep -m1 -E '^version' "$1" | grep -oE "$semver" ;;
  esac
}
ver=""
for f in gradle.properties package.json pyproject.toml Cargo.toml package-lock.json; do
  [ -e "$f" ] || continue
  v=$(declared "$f")
  [ -z "$v" ] && continue
  [ -z "$ver" ] && ver=$v
  [ "$v" = "$ver" ] && echo "- $f: $v" || echo "- $f: $v  ABWEICHUNG von $ver"
done
if [ -n "$ver" ]; then
  echo "- Version $ver steht wörtlich in:"
  files | grep -vE '\.(png|jpg|jar|lock)$|CHANGELOG|package-lock\.json' | tr '\n' '\0' | xargs -0 grep -lF "$ver" 2>/dev/null | sed 's/^/  - /'
else
  echo "- keine Version gefunden"
fi

echo
echo "## Lärmquellen (vorhanden, nicht versioniert)"
deny=$(cat .claude/settings.json .claude/settings.local.json 2>/dev/null | grep -oE 'Read\([^)]*\)')
for d in build dist target out logs run node_modules .gradle coverage playwright-report test-results \
         .wrangler .next .nuxt .cache .venv venv __pycache__ .pytest_cache .turbo; do
  [ -d "$d" ] || continue
  grep -qF "/$d/" <<<"$deny" && echo "- $d/ (Deny-Regel vorhanden)" || echo "- $d/ ungeschützt"
done
# Weitere ignorierte Ordner, die nicht in der festen Liste stehen (z. B. Worktrees, Ergebnisordner)
[ -d .claude/worktrees ] && echo "- .claude/worktrees/ ($(ls .claude/worktrees | wc -l) Worktrees, $(du -sh .claude/worktrees 2>/dev/null | cut -f1)): Repo-Kopien, Suche und Glob treffen sie mit"
git status --ignored --porcelain 2>/dev/null | sed -nE 's/^(!!|\?\?) //p' | grep '/$' \
  | grep -vE '^(build|dist|target|out|logs|run|node_modules|\.gradle|coverage|playwright-report|test-results|\.wrangler|\.next|\.nuxt|\.cache|\.venv|venv|__pycache__|\.pytest_cache|\.turbo|\.idea|\.vscode)/$' \
  | head -8 | while read -r d; do
    grep -qF "/$d" <<<"$deny" && echo "- $d (Deny-Regel vorhanden)" || echo "- $d ungeschützt ($(du -sh "$d" 2>/dev/null | cut -f1))"
  done
[ -e .gitattributes ] || echo "- keine .gitattributes (Zeilenenden nicht festgelegt)"
exit 0
