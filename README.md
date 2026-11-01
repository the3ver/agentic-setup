# agentic-setup

Agent skill `tighten-the-loop`: assesses a repo's pipeline for coding agents (edit, end of turn, commit, CI) and proposes deterministic tools that make agent builds cheaper in tokens and better in code quality. It works for any stack and any agent that reads skills (Claude Code, Codex, Gemini CLI, Copilot, Cursor and others): failure classes come from the git history, tools are chosen for the ecosystem it finds, hooks for the agents the repo uses. Also packaged as a Claude Code plugin.

## Contents

| Path | Purpose |
|---|---|
| `skills/tighten-the-loop/SKILL.md` | Procedure: map the pipeline, mine the history for failure classes, assess, choose and configure tools, plan P0 to P3. Invoked only via `/tighten-the-loop` |
| `skills/tighten-the-loop/inventory.sh` | Stack-independent facts: git state, repair commits and hotspots, file types, build manifests, task entry points, commit hooks, CI, agent configuration, version locations, noise folders |
| `skills/tighten-the-loop/CATALOG.md` | Layer model, concepts mapped from failure class to tool (examples across ecosystems), token techniques, check questions |
| `tests/smoke.sh` | Builds a throwaway Python repo with known history and checks the output of `inventory.sh` |

## Installation

The skill follows the open Agent Skills format (`SKILL.md`), so any agent that reads skills can use it.

Any agent, with the [skills CLI](https://github.com/vercel-labs/skills) (asks which agents to install for):

```bash
npx skills add the3ver/agentic-setup --skill tighten-the-loop
```

Claude Code as a plugin (invoked as `/agentic-setup:tighten-the-loop`):

```bash
claude plugin marketplace add the3ver/agentic-setup
claude plugin install agentic-setup@agentic-setup
```

By hand: copy or link `skills/tighten-the-loop/` into the agent's skill folder, for example `~/.claude/skills/`, `~/.agents/skills/` or `.github/skills/` (check your agent's docs for the path). If your agent has no skill support, tell it to read `skills/tighten-the-loop/SKILL.md` and follow it.

Claude Code honours `disable-model-invocation`; other agents rely on the description, which asks them to run the skill only on request. Hook proposals in the report target the agents found in the repo (see "Hooks per agent" in `CATALOG.md`).

## Development

```bash
uvx --from shellcheck-py shellcheck -S error skills/tighten-the-loop/inventory.sh tests/smoke.sh
bash tests/smoke.sh
```

Every bug found in the inventory first gets an expectation in `tests/smoke.sh`. Test runs against real repos produce reports; their findings feed into `SKILL.md`, `CATALOG.md` and `inventory.sh`.

Requirements: git and a bash with coreutils and awk (Git Bash on Windows). No Python, Node or jq.

The skill needs no notes system. It prints the inventory and plan in its answer and leaves the analysed repo unchanged. To keep reports, name the place in your own instructions (for example in `~/.claude/CLAUDE.md`: "Save agentic setup reports in `<path>`"); the skill then follows them. The report is written in the user's language.

## License

MIT, see [LICENSE](LICENSE).
