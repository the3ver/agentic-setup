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
py=$(command -v python || command -v python3)
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

echo
echo "## Failure history (last $depth commits)"
# Commits that repaired something are the evidence for which failure classes slip through the pipeline
# Conventional commits count by type (fix, revert, hotfix). Other conventional types count only with a
# strong keyword ("test: make flaky test deterministic"); free-form subjects also by "fix" and similar words.
strong='revert|hotfix|regress|flaky|broken|forgot|crash|deterministi|wackel|vergessen|kaputt'
weak='^fix|bug|repair|typo|oops|missing'
repairs=$(git log -"$depth" --format='%h %s' | awk -v strong="$strong" -v weak="$weak" '{
  h = $1; l = tolower(substr($0, length(h) + 2))
  if (l ~ /^(fix|revert|hotfix)([(][^)]*[)])?!?: /) { print; next }
  if (l ~ strong) { print; next }
  if (l !~ /^[a-z]+([(][^)]*[)])?!?: / && l ~ weak) print
}')
nall=$(git log -"$depth" --format=%h | wc -l)
nfix=$(grep -c . <<<"$repairs")
echo "- Repair commits: $nfix of $nall"
head -25 <<<"$repairs" | sed 's/^/  - /'
hashes=$(cut -d' ' -f1 <<<"$repairs")
touched() { for h in $hashes; do git show --format= --name-only "$h"; done | grep . | grep -viE '(^|/)changelog[^/]*$'; }
if [ -n "$hashes" ]; then
  echo "Files most often touched by repair commits (hotspots, changelogs excluded):"
  touched | sort | uniq -c | sort -rn | head -10 | sed 's/^ */- /'
  echo "Repair-commit file touches per top-level folder:"
  touched | awk -F/ '{print (NF>1 ? $1"/" : "(root)")}' | sort | uniq -c | sort -rn | head -6 | sed 's/^ */- /'
fi

echo
echo "## Code (tracked)"
echo "| Extension | Files | Lines |"
echo "|---|---|---|"
textfiles | grep -E '\.[A-Za-z0-9]+$' | sed -E 's/.*\.([A-Za-z0-9]+)$/\1/' | sort | uniq -c | sort -rn | head -10 | while read -r n ext; do
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
# Commands an agent can call: task runner targets and npm scripts
[ -f Makefile ] && echo "- make targets: $(grep -oE '^[A-Za-z0-9_.-]+:' Makefile | tr -d ':' | sort -u | head -15 | tr '\n' ' ')"
for j in justfile Justfile; do [ -f "$j" ] && echo "- just recipes: $(grep -oE '^[A-Za-z0-9_-]+( [^:]*)?:' "$j" | cut -d' ' -f1 | tr -d ':' | head -15 | tr '\n' ' ')"; done
if [ -f package.json ] && [ -n "$py" ]; then
  s=$("$py" -c "import json; d=json.load(open('package.json',encoding='utf-8')); [print(f'{k}: {v}') for k,v in d.get('scripts',{}).items()]" 2>/dev/null | tr -d '\r')
  [ -n "$s" ] && sed 's/^/- npm script /' <<<"$s"
fi
echo "Commit-time hooks:"
hp=$(git config --get core.hooksPath)
[ -n "$hp" ] && echo "- core.hooksPath: $hp"
ls .git/hooks 2>/dev/null | grep -v '\.sample$' | sed 's/^/- .git\/hooks\//'
for h in .husky .pre-commit-config.yaml lefthook.yml .lefthook.yml .githooks; do [ -e "$h" ] && echo "- $h"; done

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
denycount() { "$py" -c "import json,sys; print(len(json.load(open(sys.argv[1],encoding='utf-8')).get('permissions',{}).get('deny',[])))" "$1" 2>/dev/null || echo "?"; }
for f in .claude/settings.json .claude/settings.local.json "$HOME/.claude/settings.json"; do
  [ -e "$f" ] || continue
  ev=$(grep -oE '"(PreToolUse|PostToolUse|Stop|SubagentStop|UserPromptSubmit|SessionStart)"' "$f" | sort -u | tr -d '"' | tr '\n' ' ')
  echo "- ${f/#$HOME/\~}: hooks: ${ev:--}, deny rules: $(denycount "$f")"
done
for d in .claude/skills .claude/agents .claude/commands; do [ -d "$d" ] && echo "- $d: $(ls "$d" | tr '\n' ' ')"; done
src=$(git check-ignore -v .claude/settings.json 2>/dev/null | cut -f1)
[ -n "$src" ] && echo "- .claude/settings.json would be git-ignored (source: ${src%:*}); hooks and deny rules apply only locally"

echo
echo "## Version"
tag=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -n "$tag" ]; then
  ver=${tag#v}
  echo "- Latest tag: $tag"
  echo "- \"$ver\" appears literally in:"
  files | grep -viE '\.(png|jpg|gif|ico|jar|zip|lock)$|changelog' | tr '\n' '\0' | xargs -0 grep -lF "$ver" 2>/dev/null | head -12 | sed 's/^/  - /'
else
  echo "- no tags; find the version source by hand"
fi

echo
echo "## Noise sources (ignored or untracked folders)"
deny=$(cat .claude/settings.json .claude/settings.local.json 2>/dev/null | grep -oE 'Read\([^)]*\)')
git status --ignored --porcelain 2>/dev/null | sed -nE 's/^(!!|\?\?) //p' | grep '/$' | head -15 | while read -r d; do
  grep -qF "/${d%/}" <<<"$deny" && state="deny rule present" || state="unprotected"
  echo "- $d $(du -sh "$d" 2>/dev/null | cut -f1) ($state)"
done
[ -d .claude/worktrees ] && echo "- .claude/worktrees/ holds $(ls .claude/worktrees | wc -l) repo copies that search and glob also hit"
exit 0
