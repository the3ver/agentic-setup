---
name: analyse-project-setup
description: Analyses a repo's agentic coding setup and proposes deterministic tools (hooks, linters, architecture and mutation tests, CI) that protect quality and save LLM tokens. Produces an inventory and a phased plan; changes nothing.
disable-model-invocation: true
---

# Analyse project setup

Goal: give the agent *backpressure* in this repo. Deterministic sensors report failures immediately, a green run costs one line of context, and scripts do mechanical work instead of the LLM. The result is a plan, not an implementation.

The layer model, the tool catalog per stack and the token techniques are in [CATALOG.md](CATALOG.md). Read it before step 4.

Write the report in the user's language.

## 1. Gather prior knowledge

- Project docs in the repo: README, CLAUDE.md/AGENTS.md, CONTRIBUTING, CONTEXT.md, `docs/adr/`. Architecture rules, pitfalls and the release process often live only there.
- Project knowledge outside the repo, if the environment offers any (notes, a memory MCP server, tickets). The user's instructions say where it lives; skip this point when there is no such source.
- Read an *Agentic setup* report from an earlier run only after step 2, so it does not bias the fresh look.
- If a search over past sessions is available: search for the repo name and for keywords such as `flaky`, `red`, `forgot`, `regression`. Only count hits whose `cwd` lies in the repo, and leave out the current session and earlier runs of this skill (their text contains the keywords). Recurring failures from past sessions (red builds, forgotten files, flaky tests) are the best candidates for new rules.
- The `Failure?` and `unmerged` lines from the inventory (step 2) belong in this list too.

Done when you have a list of *failures and unwritten rules* with their source (it may be empty).

## 2. Take the inventory

`inventory.sh` sits in the same folder as this SKILL.md (given as the skill's base directory when it loads):

```bash
bash <skill-dir>/inventory.sh <repo-path>
```

The script reports git state, stack, tests, code size, quality tools found, CI workflows, agent configuration (size in tokens, including imported files), version locations and noise sources. It detects tools only by config files and patterns: "-" means "not found", not "certainly absent".

Then run the repo's fastest check command once (test script, `gradlew check` or similar) and measure duration, exit code and output lines: `time <command> 2>&1 | wc -l`. Measure exactly the command an agent runs today (for example plain `npm test`): a terser reporter flatters the current state and underestimates what a check wrapper gains. This answers check question 1. Run it in the background if it takes longer than 2 minutes. Afterwards confirm with `git status` that the run changed no tracked files.

Use both as the factual basis and read further only where a question stays open:

- Build file(s), to understand plugins and test configuration.
- The main CI workflow.
- CLAUDE.md/AGENTS.md and `.claude/settings*.json`.
- 2 to 3 typical source and test files, to spot patterns (for example "pure logic classes without framework imports"). Every visible pattern is an architecture rule that today exists only in someone's head.

Done when every row of the layer model and every row of the tool table for this stack (CATALOG.md) has a current state: present, partial or missing.

## 3. Research, only for gaps

Search the web only for what CATALOG.md does not cover for this stack: an unknown framework, unclear compatibility of a tool with the language or build version in use. Every compatibility question that stays open goes into the plan as "to verify". If there is no gap, the plan says "no research needed".

## 4. Gap analysis

Walk through the layer model and the tool table row by row and record for each row: current state, gap, concrete proposal with tool and place (hook, build, CI). Also answer every question in the *Check questions* section of CATALOG.md.

Each proposal states:
- which failure or risk it catches (from step 1 or 2),
- where it runs and how long it takes,
- whether it saves tokens, protects quality, or both.

Done when every layer and every check question is assessed and every failure from step 1 maps to a proposal.

## 5. Write the plan

Phases by effort and benefit:
- **P0** now, each under an hour: quiet check wrapper (build and/or tests) + Stop hook, deny rules for noise sources, a single version source, a first architecture rule.
- **P1** quality in the loop: formatter hook, compiler checks, consistency tests, Semgrep locally + CI.
- **P2** deeper: periodic mutation testing, generators instead of LLM handwork, changelog from commits, review subagent with guidelines, Dependabot, branch protection.
- **P3** generalisation: uniform verbs (`fmt`, `check`, `test-fast`, `test`), reusable building blocks.

The result is a Markdown report headed *Agentic setup (as of <date>)*: inventory as a table, plan P0 to P3, open points to verify, research sources.

Storage:
- The full report always appears in the answer.
- It is saved where the user's instructions keep project knowledge (CLAUDE.md/AGENTS.md, notes system). Without such an instruction, only in a place the user names; the target repo stays unchanged.
- If a report from an earlier run is already there: replace it instead of appending, and carry over points already implemented as done.

Finally: if the repo has uncommitted changes, point out that tooling changes should follow a clean commit. In a dialogue with the user, ask which phase to start with; when started by another session, only report.
