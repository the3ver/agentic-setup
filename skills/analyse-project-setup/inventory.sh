#!/usr/bin/env bash
# Stack-independent inventory of a repo's agent pipeline for analyse-project-setup.
# Collects mechanical facts only (git history, pipeline entry points, CI, agent config, noise);
# interpreting the stack and choosing tools is left to the agent.
# Usage: bash inventory.sh [repo-path] [history-depth]. Output: compact Markdown on stdout.
set -u
cd "${1:-.}" || exit 1
depth=${2:-500}
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repo: $(pwd)"; exit 1; }

files() { git ls-files; }
# Text files only (git marks binaries as -text in the index)
textfiles() { git ls-files --eol | awk '$1 != "i/-text" {print $NF}'; }
size() { local b; b=$(wc -c < "$1"); echo "$(wc -l < "$1") lines, $((b / 1024)) KB, ~$((b / 4)) tokens"; }

echo "# Inventory $(basename "$(pwd)")"
echo
echo "## Git"
echo "- Branch: $(git branch --show-current), commits: $(git rev-list --count HEAD 2>/dev/null), uncommitted files: $(git status --porcelain | wc -l)"
echo "- Remote: $(git remote get-url origin 2>/dev/null || echo -)"
total=$(git log --format=%s -50 | wc -l)
conv=$(git log --format=%s -50 | grep -cE '^[a-z]+(\(.+\))?!?:')
echo "- Conventional Commits (last 50): $conv/$total"
git for-each-ref --no-merged HEAD --format='%(refname:short) %(committerdate:short) %(subject)' refs/heads | head -8 | sed 's/^/- unmerged: /'
git worktree list | tail -n +2 | head -5 | sed 's/^/- worktree: /'
# The working tree counts: agents read and write there (the index is always LF with text=auto)
eol=$(git ls-files --eol | awk '{print $2}' | sed 's/^w\///' | grep -vE '^(-text|none|)$' | sort | uniq -c | tr -s ' ' | tr '\n' ',')
echo "- Line endings in working tree:${eol%,}$([ -e .gitattributes ] || echo '; no .gitattributes')"
git ls-files --eol | awk '$2 == "w/mixed" {print $NF}' | head -5 | sed 's/^/  - mixed: /'

echo
echo "## Failure history (last $depth commits)"
# Commits that repaired something are the evidence for which failure classes slip through the pipeline
# Conventional commits count by type (fix, revert, hotfix). Other conventional types count only with a
# strong keyword ("test: make flaky test deterministic") or as an embedded repair ("feat: fix lap bug, add x");
# free-form subjects also by "fix" and similar words.
strong='revert|hotfix|regress|flaky|broken|forgot|crash|deterministi|wackel|vergessen|kaputt'
weak='^fix|bug|repair|typo|oops|missing'
repairs=$(git log -"$depth" --format='%h %s' | awk -v strong="$strong" -v weak="$weak" '{
  h = $1; l = tolower(substr($0, length(h) + 2))
  if (l ~ /^(fix|revert|hotfix)([(][^)]*[)])?!?: /) { print; next }
  if (l ~ strong) { print; next }
  if (l ~ /^[a-z]+([(][^)]*[)])?!?: / && l ~ /(^|[ ,;:])fix |(^|[^a-z])bugs?([^a-z]|$)/) { print $0 " [embedded repair]"; next }
  if (l !~ /^[a-z]+([(][^)]*[)])?!?: / && l ~ weak) print
}')
nall=$(git log -"$depth" --format=%h | wc -l)
nfix=$(grep -c . <<<"$repairs")
echo "- Repair commits: $nfix of $nall"
head -25 <<<"$repairs" | sed 's/^/  - /'
hashes=$(cut -d' ' -f1 <<<"$repairs")
# Text files a repair commit really changed: binaries and version-only bumps are not repairs of that file
touched() {
  for h in $hashes; do
    git show --format= --numstat "$h" | while IFS=$'\t' read -r a d f; do
      [ "$a" = "-" ] && continue
      if [ $((a + d)) -le 2 ] && ! git show -U0 --format= "$h" -- "$f" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -viq version; then
        continue
      fi
      echo "$f"
    done
  done | grep -viE '(^|/)changelog[^/]*$'
}
if [ -n "$hashes" ]; then
  nbin=$(for h in $hashes; do git show --format= --numstat "$h"; done | awk -F'\t' '$1 == "-" {print $3}' | sort -u | grep -c .)
  [ "$nbin" -gt 0 ] && echo "Binary files changed by repair commits: $nbin (test artefacts written into the repo?)"
  echo "Files most often touched by repair commits (hotspots; changelogs, binaries and version bumps excluded):"
  touched | sort | uniq -c | sort -rn | head -10 | sed 's/^ */- /'
  echo "Repair-commit file touches per top-level folder:"
  touched | awk -F/ '{print (NF>1 ? $1"/" : "(root)")}' | sort | uniq -c | sort -rn | head -6 | sed 's/^ */- /'
fi

echo
echo "## Code (tracked)"
echo "| Extension | Files | Lines |"
echo "|---|---|---|"
# Dotfiles such as .gitignore have no extension
textfiles | grep -E '[^/.][^/]*\.[A-Za-z0-9]+$' | sed -E 's/.*\.([A-Za-z0-9]+)$/\1/' | sort | uniq -c | sort -rn | head -10 | while read -r n ext; do
  loc=$(textfiles | grep -E "\.${ext}$" | tr '\n' '\0' | xargs -0 cat 2>/dev/null | wc -l)
  echo "| $ext | $n | $loc |"
done
echo "Largest text files:"
textfiles | tr '\n' '\0' | xargs -0 wc -l 2>/dev/null | grep -v ' total$' | sort -rn | head -5 | sed 's/^ */- /'

echo
echo "## Pipeline entry points"
echo "Tracked files and folders at the root (build manifests, tool configs, dotfiles):"
files | awk -F/ '{print (NF>1 ? $1"/" : $1)}' | sort -u | tr '\n' ' ' | fold -w 160 -s | sed 's/^/  /'
echo
echo "Nested build manifests (depth 2-3):"
files | grep -E '^[^/]+/([^/]+/)?[^/]+$' | grep -E '/(Makefile|justfile|Taskfile\.ya?ml|package\.json|pyproject\.toml|Cargo\.toml|go\.mod|pom\.xml|build\.gradle(\.kts)?|[^/]+\.csproj|CMakeLists\.txt|mix\.exs|Gemfile|composer\.json|pubspec\.yaml|Package\.swift|build\.sbt|flake\.nix|Dockerfile)$' | head -10 | sed 's/^/- /'
echo "Commands an agent can call:"
# Task runner targets, npm scripts, shell scripts, commands documented for humans
[ -f Makefile ] && echo "- make targets: $(grep -oE '^[A-Za-z0-9_.-]+:' Makefile | tr -d ':' | sort -u | head -15 | tr '\n' ' ')"
for j in justfile Justfile; do [ -f "$j" ] && echo "- just recipes: $(grep -oE '^[A-Za-z0-9_-]+( [^:]*)?:' "$j" | cut -d' ' -f1 | tr -d ':' | head -15 | tr '\n' ' ')"; done
# JSON without a parser: join the lines first, so one-line and multi-line objects look the same
if [ -f package.json ]; then
  tr -d '\r\n' < package.json | grep -oE '"scripts" *: *\{[^}]*\}' | sed -E 's/^"scripts" *: *\{//' \
    | grep -oE '"[^"]+" *: *"([^"\\]|\\.)*"' | sed -E 's/^"([^"]+)" *: *"(.*)"$/- npm script \1: \2/'
fi
files | grep -E '^([^/]+|scripts/[^/]+)\.(sh|bat|cmd|ps1)$' | head -10 | sed 's/^/- script: /'
# Commands documented for humans: shell lines in fenced blocks of README/CONTRIBUTING/AGENTS that build or test
for doc in README.md CONTRIBUTING.md AGENTS.md CLAUDE.md docs/CONTRIBUTING.md; do
  [ -f "$doc" ] || continue
  awk '/^```/ {inblock = !inblock; next} inblock' "$doc" | grep -vE '[│├└─]|^\s*#' \
    | grep -iE '(^|[ /])(test|tests|pytest|unittest|build|check|lint|make|gradlew?|mvn|cargo|go|dotnet|npm|pnpm|yarn|tox|nox)( |$)' \
    | head -4 | sed "s|^|- documented in $doc: |"
done
# Test runner settings that hide flaky tests (retries) or change what the agent reads (reporter)
for c in $(files | grep -E '(^|/)(playwright|vitest|jest|cypress)\.config\.[cm]?[jt]s$' | head -4); do
  r=$(grep -oE '(retries|fullyParallel|reporter|workers|bail|testTimeout) *: *[^,}]+' "$c" | head -5 | tr '\n' ';')
  [ -n "$r" ] && echo "- $c: ${r%;}"
done
echo "Commit-time hooks:"
{
  hp=$(git config --get core.hooksPath)
  [ -n "$hp" ] && echo "- core.hooksPath: $hp"
  ls .git/hooks 2>/dev/null | grep -v '\.sample$' | sed 's/^/- .git\/hooks\//'
  for h in .husky .pre-commit-config.yaml lefthook.yml .lefthook.yml .githooks; do [ -e "$h" ] && echo "- $h"; done
} | grep . || echo "- none"

echo
echo "## CI"
found=0
for w in .github/workflows/*.y*ml .gitlab-ci.yml Jenkinsfile .circleci/config.yml azure-pipelines.yml bitbucket-pipelines.yml .woodpecker.yml; do
  [ -f "$w" ] || continue
  found=1
  trig=$(grep -A8 -E '^on:' "$w" 2>/dev/null | grep -oE '(push|pull_request|merge_request|schedule|workflow_dispatch|release|tags)' | sort -u | tr '\n' ' ')
  runs=$(grep -E '^\s*(- )?(run|script):' "$w" | sed -E 's/^\s*(- )?(run|script):\s*//' | grep . | head -6 | tr '\n' ';')
  echo "- $w [${trig% }] runs: ${runs:--}"
  grep -q 'continue-on-error' "$w" && echo "  - continue-on-error present"
  grep -qE 'upload-sarif|codeql|sast' "$w" && echo "  - code scanning present"
  grep -hoE "(node|java|python|go|dotnet|ruby)-version: *['\"]?[^'\" ]+" "$w" | sort -u | sed 's/^/  - runtime /'
done
[ $found -eq 0 ] && echo "- no CI configuration found"
for f in .github/dependabot.yml renovate.json .github/renovate.json .github/CODEOWNERS; do [ -e "$f" ] && echo "- $f"; done

echo
echo "## Agent configuration"
seen=" "
# The user's global instructions load in every session too
for f in "$HOME/.claude/CLAUDE.md" CLAUDE.md AGENTS.md GEMINI.md .agents/AGENTS.md .cursorrules .github/copilot-instructions.md .mcp.json; do
  [ -e "$f" ] || continue
  # Do not count files already measured as an import twice
  [[ $seen == *" $f "* ]] && continue
  echo "- ${f/#$HOME/\~} ($(size "$f"))"
  for imp in $(grep -oE '^@[^ ]+' "$f" | cut -c2- | tr -d '\r'); do
    imp=${imp/#\~/$HOME}
    seen="$seen$imp "
    [ -e "$imp" ] && echo "  - imports $imp ($(size "$imp"))" || echo "  - imports $imp (missing)"
  done
done
# Strings inside the deny array; the first match is the key "deny" itself
denycount() { tr -d '\r\n' < "$1" | grep -oE '"deny" *: *\[[^]]*\]' | grep -oE '"([^"\\]|\\.)*"' | tail -n +2 | grep -c .; }
for f in .claude/settings.json .claude/settings.local.json "$HOME/.claude/settings.json"; do
  [ -e "$f" ] || continue
  ev=$(grep -oE '"(PreToolUse|PostToolUse|Stop|SubagentStop|UserPromptSubmit|SessionStart)"' "$f" | sort -u | tr -d '"' | tr '\n' ' ')
  echo "- ${f/#$HOME/\~}: hooks: ${ev:--}, deny rules: $(denycount "$f")"
done
for d in .agents .claude .cursor; do
  [ -d "$d" ] && git check-ignore -q "$d/" && echo "- $d/ is git-ignored; the agent configuration in it stays on this machine"
done
for d in .claude/skills .claude/agents .claude/commands; do [ -d "$d" ] && echo "- $d: $(ls "$d" | tr '\n' ' ')"; done
src=$(git check-ignore -v .claude/settings.json 2>/dev/null | cut -f1)
if [ -n "$src" ]; then
  echo "- .claude/settings.json would be git-ignored (source: ${src%:*}); hooks and deny rules apply only locally"
else
  echo "- .claude/settings.json would be tracked; hooks and deny rules can travel with the repo"
fi

echo
echo "## Version"
desc=$(git describe --tags 2>/dev/null)
echo "- Latest tag: ${desc:-none}$([ -n "$desc" ] && [ "$desc" != "$(git describe --tags --abbrev=0 2>/dev/null)" ] && echo ' (HEAD is past the tag)')"
# Root manifests and lockfiles always with their value: drift there can lie outside the version family
# JSON: the first "version" key is the top-level one in these manifests; npm v2+ lockfiles repeat the
# root version under packages[""]. TOML: "version =" inside the named table.
jsonver() { tr -d '\r\n' < "$1" | grep -oE "$2\"version\" *: *\"[^\"]+\"" | head -1 | sed -E 's/.*"([^"]+)"$/\1/'; }
tomlver() {
  awk -v want="$2" '/^\[/ { sec = $0; gsub(/[][ \t\r]/, "", sec); next }
    sec == want && /^version *=/ { sub(/^version *= *"/, ""); sub(/".*$/, ""); print; exit }' "$1"
}
mv=$(
  for f in package.json package-lock.json composer.json deno.json; do
    [ -f "$f" ] || continue
    v=$(jsonver "$f" '')
    [ -n "$v" ] && echo "$f $v"
    r=$(jsonver "$f" '"packages" *: *\{ *"" *: *\{[^}]*')
    [ -n "$r" ] && [ "$r" != "$v" ] && echo "$f:packages[\"\"] $r"
  done
  for spec in pyproject.toml:project pyproject.toml:tool.poetry Cargo.toml:package; do
    f=${spec%%:*}
    [ -f "$f" ] || continue
    v=$(tomlver "$f" "${spec#*:}")
    [ -n "$v" ] && echo "$f $v" && [ "$f" = pyproject.toml ] && break
  done
)
if [ -n "$mv" ]; then
  echo "- Manifest versions: $(tr '\n' ',' <<<"$mv" | sed 's/,$//; s/,/, /g')"
  [ "$(cut -d' ' -f2 <<<"$mv" | sort -u | wc -l)" -gt 1 ] && echo "- MISMATCH: manifests and lockfiles disagree"
fi
# Pass 1: values declared under a bare version key (not loader_version, not a plugin or dependency line,
# not in tests), as "x.y.z file". "0, 3, 2, 0" (Windows resources) counts as 0.3.2.
# Pass 2: the project's version family comes from the latest tag, else from the most often declared value;
# every other value of that major.minor family anywhere in the files is a stale copy.
vfiles=$(textfiles | grep -viE '(^|/)changelog|\.lock$|-lock\.json$|(^|/)(node_modules|vendor)/|(^|/)(test|tests|spec|__tests__)/|[._-](test|spec)\.')
decl=$(tr '\n' '\0' <<<"$vfiles" \
  | xargs -0 grep -HiE "(^|[^A-Za-z0-9_])(__version__|version|filevers|prodvers|FileVersion|ProductVersion)([^A-Za-z0-9_]|$)" 2>/dev/null \
  | grep -viE "(^[^:]+:.*(\bid\b|plugin|implementation|dependenc|classpath|uses:|[a-z]_version|version_[a-z]|-version))" \
  | sed -E 's/([0-9]+), ?([0-9]+), ?([0-9]+)/\1.\2.\3/g' \
  | awk -F: '{ f = $1; line = substr($0, length(f) + 2)
      while (match(line, /[0-9]+\.[0-9]+\.[0-9]+/)) { print substr(line, RSTART, RLENGTH), f; line = substr(line, RSTART + RLENGTH) } }' \
  | sort -u)
tagged=$(git describe --tags --abbrev=0 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$tagged" ]; then
  family=${tagged%.*}
else
  family=$(cut -d' ' -f1 <<<"$decl" | grep . | sort | uniq -c | sort -rn | awk 'NR==1 {print $2}')
  family=${family%.*}
fi
if [ -n "$family" ]; then
  current=$(cut -d' ' -f1 <<<"$decl" | grep -E "^${family//./\\.}\." | sort -uV | tail -1)
  [ -z "$current" ] && current=$tagged
  echo "- Current version: $current, declared in: $(grep "^$current " <<<"$decl" | cut -d' ' -f2- | head -6 | tr '\n' ' ')"
  stale=$(tr '\n' '\0' <<<"$vfiles" | xargs -0 grep -HoE "(^|[^0-9.])v?${family//./\\.}\.[0-9]+([^0-9.]|$)" 2>/dev/null \
    | sed -E "s/^([^:]+):.*(${family//./\\.}\.[0-9]+).*/\2 \1/" | grep -v "^$current " | sort -u)
  if [ -n "$stale" ]; then
    echo "- MISMATCH: other versions of the $family family:"
    sed -E 's/^([^ ]+) (.*)$/  - \1 in \2/' <<<"$stale" | head -8
  fi
else
  echo "- no declared version found; find the version source by hand"
fi

echo
echo "## Noise sources (ignored or untracked folders)"
deny=$(cat .claude/settings.json .claude/settings.local.json 2>/dev/null | grep -oE 'Read\([^)]*\)')
git status --ignored --porcelain 2>/dev/null | sed -nE 's/^(!!|\?\?) //p' | grep '/$' | head -15 | while read -r d; do
  grep -qF "/${d%/}" <<<"$deny" && state="deny rule present" || state="unprotected"
  echo "- $d $(du -sh "$d" 2>/dev/null | cut -f1) ($state)"
done
[ -d .claude/worktrees ] && echo "- .claude/worktrees/ holds $(ls .claude/worktrees | wc -l) repo copies that search and glob also hit"
# Ignored files that may hold secrets or personal data: keep them away from the agent too
sens=$(git status --ignored --porcelain --untracked-files=all 2>/dev/null | sed -nE 's/^!! //p' \
  | grep -iE '(^|/)(\.env[^/]*|config[^/]*\.(json|ya?ml|toml|ini)|[^/]*secret[^/]*|[^/]*\.(pem|key|p12|pfx|log|csv|sqlite|db))$' \
  | grep -vE '(^|/)(node_modules|\.venv|venv|build|dist|target|\.gradle)/' | head -8)
if [ -n "$sens" ]; then
  echo "Ignored files that may be sensitive:"
  while read -r f; do
    grep -qF "${f}" <<<"$deny" && state="deny rule present" || state="no deny rule"
    echo "- $f ($state)"
  done <<<"$sens"
fi
exit 0
