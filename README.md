# agentic-setup

Claude Code plugin for agentic coding with deterministic tools. It gives the agent *backpressure*: formatters, compiler checks, architecture and consistency tests report failures immediately, a green run costs one line of context, and scripts do mechanical work instead of the LLM.

## Contents

| Path | Purpose |
|---|---|
| `skills/analyse-project-setup/SKILL.md` | Procedure: prior knowledge, inventory, gap analysis, plan P0 to P3. Invoked only via `/analyse-project-setup` |
| `skills/analyse-project-setup/inventory.sh` | Deterministic inventory of a repo (git, stack, tests, tools, CI, agent configuration, versions, noise sources) |
| `skills/analyse-project-setup/CATALOG.md` | Layer model, tools per stack, Semgrep ideas, token techniques, check questions |
| `tests/smoke.sh` | Builds a throwaway repo with known findings and checks the output of `inventory.sh` |

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

Requirements: Git Bash or another bash, git, Python 3 (for JSON).

The skill needs no notes system. It prints the inventory and plan in its answer and leaves the analysed repo unchanged. To keep reports, name the place in your own instructions (for example in `~/.claude/CLAUDE.md`: "Save agentic setup reports in `<path>`"); the skill then follows them. The report is written in the user's language.

## License

MIT, see [LICENSE](LICENSE).
