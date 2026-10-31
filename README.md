# agentic-setup

Claude Code plugin that assesses a repo's pipeline for coding agents (edit, end of turn, commit, CI) and proposes deterministic tools that make agent builds cheaper in tokens and better in code quality. It works for any stack: failure classes come from the git history, tools are chosen for the ecosystem it finds.

## Contents

| Path | Purpose |
|---|---|
| `skills/analyse-project-setup/SKILL.md` | Procedure: map the pipeline, mine the history for failure classes, assess, choose and configure tools, plan P0 to P3. Invoked only via `/analyse-project-setup` |
| `skills/analyse-project-setup/inventory.sh` | Stack-independent facts: git state, repair commits and hotspots, file types, build manifests, task entry points, commit hooks, CI, agent configuration, version locations, noise folders |
| `skills/analyse-project-setup/CATALOG.md` | Layer model, concepts mapped from failure class to tool (examples across ecosystems), token techniques, check questions |
| `tests/smoke.sh` | Builds a throwaway Python repo with known history and checks the output of `inventory.sh` |

## Installation

```bash
claude plugin marketplace add the3ver/agentic-setup
claude plugin install agentic-setup@agentic-setup
```

## Development

```bash
uvx --from shellcheck-py shellcheck -S error skills/analyse-project-setup/inventory.sh tests/smoke.sh
bash tests/smoke.sh
```

Every bug found in the inventory first gets an expectation in `tests/smoke.sh`. Test runs against real repos produce reports; their findings feed into `SKILL.md`, `CATALOG.md` and `inventory.sh`.

Requirements: git and a bash with coreutils and awk (Git Bash on Windows). No Python, Node or jq.

The skill needs no notes system. It prints the inventory and plan in its answer and leaves the analysed repo unchanged. To keep reports, name the place in your own instructions (for example in `~/.claude/CLAUDE.md`: "Save agentic setup reports in `<path>`"); the skill then follows them. The report is written in the user's language.

## License

MIT, see [LICENSE](LICENSE).
