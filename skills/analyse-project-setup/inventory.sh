#!/usr/bin/env bash
# Deterministic inventory of a repo for analyse-project-setup.
# Usage: bash inventory.sh [repo-path]. Output: compact Markdown on stdout.
set -u
cd "${1:-.}" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repo: $(pwd)"; exit 1; }

files() { git ls-files; }
py=$(command -v python || command -v python3)
has() { [ -e "$1" ] && echo "yes" || echo "-"; }
grepf() { grep -l -E "$1" "${@:2}" 2>/dev/null | head -1; }

echo "# Inventory $(basename "$(pwd)")"
echo
echo "## Git"
echo "- Branch: $(git branch --show-current), Commits: $(git rev-list --count HEAD 2>/dev/null)"
echo "- Uncommitted: $(git status --porcelain | wc -l) files"
total=$(git log --format=%s -50 | wc -l)
conv=$(git log --format=%s -50 | grep -cE '^(feat|fix|refactor|docs|test|chore|style|perf|build|ci)(\(.+\))?!?:')
echo "- Conventional Commits (last 50): $conv/$total"
echo "- Remote: $(git remote get-url origin 2>/dev/null || echo -)"
# Failure candidates for step 1: commits that mention flaky tests, reverts or test repairs
git log --format='%h %s' -300 | grep -iE 'flaky|wackel|revert|fix\(test|deterministisch|vergessen|forgot' | head -8 | sed 's/^/  - Failure? /'
# Stranded work: branches not merged into the current branch, and extra worktrees
git for-each-ref --no-merged HEAD --format='%(refname:short) %(committerdate:short) %(subject)' refs/heads | head -8 | sed 's/^/  - unmerged: /'
git worktree list | tail -n +2 | head -5 | sed 's/^/  - Worktree: /'
# The working tree counts: agents read and write there (the index is always LF with text=auto)
eol=$(git ls-files --eol | awk '{print $2}' | sed 's/^w\///' | grep -vE '^(-text|none|)$' | sort | uniq -c | tr -s ' ' | tr '\n' ',')
echo "- Line endings in working tree:${eol%,}"

echo
echo "## Stack"
for f in build.gradle build.gradle.kts settings.gradle pom.xml package.json pnpm-lock.yaml yarn.lock \
         pyproject.toml requirements.txt Cargo.toml go.mod tsconfig.json vite.config.ts vite.config.js; do
  [ -e "$f" ] && echo "- $f"
done
ls *.csproj *.sln 2>/dev/null | sed 's/^/- /'
if [ -e package.json ]; then
  if grep -q '"type": *"module"' package.json; then
    echo "- ES modules (type: module)"
  elif files | grep -E '\.html$' | tr '\n' '\0' | xargs -0 grep -lq '<script[^>]*type="module"' 2>/dev/null; then
    echo "- ES modules in the browser (<script type=\"module\">)"
  fi
  if ! grep -qE '"build"\s*:' package.json && ! ls vite.config.* webpack.config.* rollup.config.* esbuild.* tsconfig.json >/dev/null 2>&1; then
    echo "- No build step (no build script, no bundler, no tsconfig)"
  fi
fi
node_v=$(cat .nvmrc .node-version 2>/dev/null | head -1)
[ -z "$node_v" ] && [ -d .github/workflows ] && node_v=$(grep -hoE "node-version: *['\"]?[0-9.x]+" .github/workflows/* 2>/dev/null | head -1 | grep -oE '[0-9.x]+$')
[ -n "$node_v" ] && echo "- Node version (project/CI): $node_v"
[ -e package.json ] && command -v node >/dev/null && echo "- Node local: $(node --version)"
java_v=$(grep -hoE "(languageVersion.*of\(|release = |java-version: *['\"]?)[0-9]+" build.gradle* .github/workflows/* 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')
[ -n "$java_v" ] && echo "- Java version(s): $java_v"

echo
echo "## Tests"
for f in playwright.config.* vitest.config.* jest.config.* pytest.ini; do [ -e "$f" ] && echo "- Config: $f"; done
[ -e package.json ] && grep -oE '"(vitest|jest|mocha|@playwright/test|node:test)"' package.json | sort -u | sed 's/^/- Framework: /'
grep -qiE 'junit|testng|spock' build.gradle* pom.xml 2>/dev/null && echo "- Framework: JUnit/TestNG (build file)"
grep -q pytest pyproject.toml 2>/dev/null && echo "- Framework: pytest"
testfiles=$(files | grep -iE '(^|/)(test|tests|__tests__|spec)/|[._-](test|spec)\.[a-z]+$|Test\.(java|kt)$')
if [ -n "$testfiles" ]; then
  cases=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE '^\s*(test|it)(\.only|\.skip)?\(|@(Test|ParameterizedTest)\b|^\s*def test_' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Test cases (rough count): ${cases:-?}"
  sleeps=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE 'waitForTimeout|Thread\.sleep|time\.sleep|setTimeout\(' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Fixed waits in tests (waitForTimeout, sleep, setTimeout): ${sleeps:-0}"
  skips=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -hcE '\.(skip|only)\(|@Disabled|@Ignore|pytest\.mark\.skip' 2>/dev/null | awk '{s+=$1} END{print s+0}')
  echo "- Skipped/focused tests: ${skips:-0}"
  # Structure tests: tests that read source code and check it against rules (guard tests)
  guards=$(echo "$testfiles" | tr '\n' '\0' | xargs -0 grep -lE "(readFileSync|readdirSync|Files\.(readString|walk|lines)|open\().*(src|main)|archunit|ArchRule" 2>/dev/null | tr '\n' ' ')
  echo "- Structure tests (read source or ArchUnit): ${guards:--}"
  grep -hoE '(retries|reporter|forbidOnly|workers): *[^,}]+' playwright.config.* 2>/dev/null | sort -u | sed 's/^/- Playwright /'
fi

echo
echo "## Code (tracked)"
echo "| Extension | Files | Lines | of which test files |"
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
echo "Largest source files:"
files | grep -E '\.(java|kt|ts|tsx|js|vue|py|go|rs|cs)$' | grep -viE 'test|spec|\.min\.' \
  | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null | grep -v ' total$' | sort -rn | head -5 | sed 's/^ */- /'

# JS: modules without DOM access are candidates for fast Node unit and mutation tests
jsmods=$(files | grep -E '\.m?js$' | grep -viE '(^|/)(test|tests|spec|node_modules|dist)/|\.(spec|test|min|config)\.')
if [ -n "$jsmods" ]; then
  pure=""; npure=0; ndom=0
  for f in $jsmods; do
    if grep -qE '\b(document|window|navigator|localStorage)\.' "$f"; then ndom=$((ndom + 1))
    else npure=$((npure + 1)); pure="$pure $(basename "$f")"; fi
  done
  echo
  echo "JS modules: $ndom with DOM access, $npure without:$(echo "$pure" | cut -c1-300)"
  echo "Most imports:"
  for f in $jsmods; do echo "$(grep -cE '^\s*import ' "$f") $f"; done | sort -rn | head -3 | sed 's/^/- /'
fi

echo
echo "## Quality tools (config found)"
buildfiles=$(ls build.gradle build.gradle.kts pom.xml package.json pyproject.toml 2>/dev/null)
check() { # name, regex in build files, file globs
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
check "Compiler checks" 'errorprone|nullaway|"strict": *true|mypy|pyright' tsconfig.json
check "Architecture rules" 'archunit|dependency-cruiser|import-linter|eslint-plugin-boundaries' .dependency-cruiser*
check "Mutation Testing" 'pitest|stryker|mutmut' stryker.conf*
check "Coverage" 'jacoco|kover|"c8"|"nyc"|--coverage|pytest-cov'
check "Semgrep" '' .semgrep* .semgrep.yml semgrep.yml
check "Dead code / deps" 'knip|depcheck|vulture|unused' knip.json
check "Git hooks" 'husky|lint-staged|lefthook' .husky .pre-commit-config.yaml lefthook.yml .githooks
check "Task runner" '' justfile Justfile Makefile Taskfile.yml
check "Code generation" 'fabric-datagen|datagen|openapi-generator|codegen'

if [ -e package.json ]; then
  echo
  echo "package.json scripts:"
  # Parse real JSON: sed ranges break on one-line objects
  # Python on Windows writes CRLF; the \r would break every name comparison
  pkg() { "$py" -c "import json; d=json.load(open('package.json',encoding='utf-8')); $1" 2>/dev/null | tr -d '\r'; }
  scripts=$(pkg "[print(f'{k}: {v}') for k,v in d.get('scripts',{}).items()]")
  [ -n "$scripts" ] && sed 's/^/- /' <<<"$scripts"
  # Dependencies that are neither imported nor called as a CLI in an npm script (candidates)
  deps=$(pkg "[print(k) for s in ('dependencies','devDependencies') for k in d.get(s,{})]")
  code=$(files | grep -E '\.(m?js|cjs|ts|tsx|vue|svelte|html)$')
  unused=""
  for d in $deps; do
    echo "$code" | tr '\n' '\0' | xargs -0 grep -qE "(from|require\(|import\() *['\"]${d}['\"/]" 2>/dev/null && continue
    grep -qE "(^|[\" &;])${d##*/}( |\"|$)|${d#@}" <<<"$scripts" && continue
    [ "$d" = "@playwright/test" ] && grep -q playwright <<<"$scripts" && continue
    unused="$unused $d"
  done
  [ -n "$unused" ] && echo "- Dependencies not found in code:$unused"
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
  echo "- no workflows"
fi
echo "- Dependabot: $(has .github/dependabot.yml), Renovate: $(ls renovate.json* .github/renovate.json* 2>/dev/null | head -1 | grep . || echo -), CODEOWNERS: $(has .github/CODEOWNERS)"

echo
echo "## Agent configuration"
# Size in bytes is what counts for context, not line count (~4 bytes per token)
size() { local b; b=$(wc -c < "$1"); echo "$(wc -l < "$1") lines, $((b / 1024)) KB, ~$((b / 4)) tokens"; }
seen=" "
for f in CLAUDE.md AGENTS.md GEMINI.md .agents/AGENTS.md .cursorrules .github/copilot-instructions.md .mcp.json; do
  [ -e "$f" ] || continue
  # Do not count files already measured as an import twice
  [[ $seen == *" $f "* ]] && continue
  echo "- $f ($(size "$f"))"
  for imp in $(grep -oE '^@[^ ]+' "$f" | cut -c2-); do
    imp=${imp/#\~/$HOME}
    seen="$seen$imp "
    [ -e "$imp" ] && echo "  - imports $imp ($(size "$imp"))" || echo "  - imports $imp (missing)"
  done
done
for f in .claude/settings.json .claude/settings.local.json; do
  [ -e "$f" ] || continue
  echo "- $f: hooks=$(grep -c '"hooks"' "$f"), permissions=$(grep -c '"permissions"' "$f")"
  grep -oE '"(PreToolUse|PostToolUse|Stop|SubagentStop|UserPromptSubmit|SessionStart)"' "$f" | sort -u | sed 's/^/  - hook event /'
done
[ -d .claude/skills ] && echo "- Project skills: $(ls .claude/skills | tr '\n' ' ')"
[ -d .claude/agents ] && echo "- Project agents: $(ls .claude/agents | tr '\n' ' ')"
[ -d .claude/commands ] && echo "- Project commands: $(ls .claude/commands | tr '\n' ' ')"
src=$(git check-ignore -v .claude/settings.json 2>/dev/null | cut -f1)
[ -n "$src" ] && echo "- .claude/settings.json would be git-ignored (source: ${src%:*}); hooks and deny rules apply only locally$([ -e .claude/settings.json ] || echo '; file does not exist yet')"
denycount() { "$py" -c "import json,sys; print(len(json.load(open(sys.argv[1],encoding='utf-8')).get('permissions',{}).get('deny',[])))" "$1" 2>/dev/null || echo "?"; }
g=$HOME/.claude/settings.json
if [ -e "$g" ]; then
  ev=$(grep -oE '"(PreToolUse|PostToolUse|Stop|UserPromptSubmit|SessionStart)"' "$g" | sort -u | tr -d '"' | tr '\n' ' ')
  echo "- Global ~/.claude/settings.json: hooks: ${ev:--}, deny rules: $(denycount "$g")"
fi
[ -e .claude/settings.json ] && echo "- Project deny rules: $(denycount .claude/settings.json)"
# Scripts outside source and test folders that execute commands (agent bridges, automation)
for f in $(files | grep -E '\.(py|sh|mjs|js|ps1)$' | grep -vE '^(src|test|tests|docs|node_modules|gradle)/|(^|/)gradlew'); do
  grep -qE 'subprocess|child_process|os\.system|exec(Sync)?\(|eval\(|Invoke-Expression' "$f" && echo "- Warning: $f executes commands"
done | head -8

echo
echo "## Version locations"
semver='[0-9]+\.[0-9]+\.[0-9]+'
declared() { # file, version declared in that file
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
  [ "$v" = "$ver" ] && echo "- $f: $v" || echo "- $f: $v  MISMATCH with $ver"
done
if [ -n "$ver" ]; then
  echo "- Version $ver appears literally in:"
  files | grep -vE '\.(png|jpg|jar|lock)$|CHANGELOG|package-lock\.json' | tr '\n' '\0' | xargs -0 grep -lF "$ver" 2>/dev/null | sed 's/^/  - /'
else
  echo "- no version found"
fi

echo
echo "## Noise sources (present, untracked)"
deny=$(cat .claude/settings.json .claude/settings.local.json 2>/dev/null | grep -oE 'Read\([^)]*\)')
for d in build dist target out logs run node_modules .gradle coverage playwright-report test-results \
         .wrangler .next .nuxt .cache .venv venv __pycache__ .pytest_cache .turbo; do
  [ -d "$d" ] || continue
  grep -qF "/$d/" <<<"$deny" && echo "- $d/ (deny rule present)" || echo "- $d/ unprotected"
done
# Further ignored folders not in the fixed list (for example worktrees, result folders)
[ -d .claude/worktrees ] && echo "- .claude/worktrees/ ($(ls .claude/worktrees | wc -l) worktrees, $(du -sh .claude/worktrees 2>/dev/null | cut -f1)): repo copies that search and glob also hit"
git status --ignored --porcelain 2>/dev/null | sed -nE 's/^(!!|\?\?) //p' | grep '/$' \
  | grep -vE '^(build|dist|target|out|logs|run|node_modules|\.gradle|coverage|playwright-report|test-results|\.wrangler|\.next|\.nuxt|\.cache|\.venv|venv|__pycache__|\.pytest_cache|\.turbo|\.idea|\.vscode)/$' \
  | head -8 | while read -r d; do
    grep -qF "/$d" <<<"$deny" && echo "- $d (deny rule present)" || echo "- $d unprotected ($(du -sh "$d" 2>/dev/null | cut -f1))"
  done
[ -e .gitattributes ] || echo "- no .gitattributes (line endings not fixed)"
exit 0
