---
name: tighten-the-loop
description: Assesses a repo's pipeline (edit, end of turn, commit, CI) for the coding agent and proposes deterministic tools, configured for this project, that make agent builds cheaper in tokens and better in code quality. Works for any stack and any coding agent. Produces an assessment and a phased plan; changes nothing. Run it only when the user asks for it by name, not on your own initiative.
# Claude Code only; other agents rely on the last sentence of the description
disable-model-invocation: true
---

# Tighten the loop

Goal: give the coding agent *backpressure*. The pipeline should report failures deterministically and early, cost one line of context when green, and leave mechanical work to scripts. The subject is the **pipeline**, not the code: what runs at which layer, what it costs, and which failure classes slip through it.

[CATALOG.md](CATALOG.md) holds the layer model, the concepts (each with the failure class it catches) and the token techniques. Read it before step 3. Its tool names are examples; choose the tools of the stack you find.

Proposals come from two sources:
- **Baseline:** concepts marked *baseline* in CATALOG.md fit every repo of the stack and need no history. Propose every missing one.
- **Evidence:** concepts marked *evidence* in CATALOG.md are proposed and prioritised from evidence: repair commits, recurring review findings, visible structure. With little or no history, take the typical failure classes of the stack and the patterns visible in the code structure, mark those proposals "preventive, no evidence yet", and recommend re-running the analysis once the history has grown.

Write the report in the user's language.

## 1. Map the pipeline

`inventory.sh` sits in the same folder as this SKILL.md (given as the skill's base directory when it loads):

```bash
bash <skill-dir>/inventory.sh <repo-path> [history-depth, default 500]
```

It collects stack-independent facts only: git state, repair commits and hotspots, file types, root files and build manifests, task runner entry points, commit hooks, CI jobs, agent configuration, version locations, noise folders. "-" or a missing line means "not found by the script", not "certainly absent".

From these facts and the files they point to, identify:
- **Stack and ecosystem:** languages, build tool, package manager, test framework.
- **The pipeline per layer** (CATALOG.md): what runs on edit, at end of turn, on commit, in CI, periodically, and what the agent may read.
- **The check command** an agent would use today: a task runner target or npm script if there is one, else the command documented in README/AGENTS.md (the inventory lists both), else the framework's default. Run it once and measure duration, exit code and output lines:
  `time <command> > <scratch>/check.out 2>&1; echo "exit=$?"; wc -l < <scratch>/check.out`
  Measure the command as an agent calls it, not with a terser reporter; if one flag changes the line count a lot (for example `-v`), report both numbers. Run it in the background if it takes longer than 2 minutes.
- **Baseline tools, measured read-only:** for each baseline concept that is missing, run the stack's usual tool once with default rules through a throwaway runner (`uvx`, `npx --yes`, `pnpm dlx`, `go run`, `dotnet tool exec` or similar) in check mode. Use the tool's summary or count output (CATALOG.md field notes), not the full listing. For formatters, measure a second time with the style options the code already follows (quotes, line width, semicolons): only that count shows the real churn. The finding counts decide in step 4 how to handle existing violations. Keep caches outside the repo (`--no-cache`, `--cache-dir <scratch>`).

Before and after any command: record `git status --porcelain --ignored --untracked-files=all` (without `--untracked-files=all`, new files inside an already ignored folder stay invisible), then remove what the run created and restore changed tracked files with `git checkout -- <path>`. If the check command itself changes tracked files (screenshots, snapshots, reports), that is a finding: the tests are not hermetic. The skill changes nothing in the target repo.

Done when every layer of the model has a current state (present, partial, missing), the check command has measured numbers, and every missing baseline tool has a finding count or a reason why it could not run.

## 2. Mine the history for failure classes

The repair commits from the inventory are the evidence of what the pipeline lets through. For each repair commit (all of them up to about 30, otherwise the most recent 30 plus the hotspots):
- read its diff (`git show --stat <hash>`, then the relevant hunks),
- name the **failure class** (for example: unformatted code, null/undefined access, wrong layer dependency, forgotten registration or resource, flaky test from fixed waits or real time, version drift, broken CI config, missing translation),
- find the commit that introduced the defect (`git log -L <range>:<file> <fix>^` or `git blame <fix>^ -- <file>`). When the introducing commit is itself a repair, you have a **fix chain**: nothing checked between the two commits. Report fix chains; they are the strongest argument for layer 2. Also report the same feature or code region repaired several times, even without a strict chain. For a bundled fix (many topics, many files) assign only the hunks you can, and say which part stays unassigned,
- decide whether a deterministic tool would have caught it, and at which layer. Where cheap, prove it: run the proposed tool on the introducing state and note whether it fails. A single file (`git show <commit>:<file>`) suffices for formatters and linters; tools that need the module graph (type checkers, compilers) need the tree: `git archive <commit> <dirs> | tar -x -C <scratch>`.

The inventory marks repairs hidden in other commit types ("feat: fix lap bug, add selector") as `[embedded repair]`; treat them like any repair.

Search the current code for a pattern only to configure a rule for a failure class you have evidence or a preventive reason for: count existing occurrences to choose between failing on all, a baseline, or checking only changed lines. Do not scan the code for patterns without such a reason.

With fewer than 3 repair commits this step yields little: say so, and rely on the baseline plus the stack's typical failure classes (research them if needed). The total commit count does not matter.

Further sources for failure classes, if available: the project's docs (README, CLAUDE.md/AGENTS.md, CONTRIBUTING, ADRs), notes systems named in the user's instructions, and past sessions of a coding agent when the user's instructions name that source together with a way to search it (only hits whose `cwd` lies in the repo, excluding runs of this skill). If no such source exists, say so in the report. Read an `## Agentic setup` report from an earlier run only after this step, so it does not bias the fresh look.

Done when every repair commit you read has a failure class, its introducing commit (or "not found") and a verdict (tool could catch it at layer X / needs judgement / one-off).

## 3. Assess the pipeline

For each layer, record:
- **Cost:** duration, output lines when green and when red, noise the agent reads (build output, logs, reports, repo copies).
- **Quality:** which failure classes from step 2 pass this layer undetected.

Answer the check questions in CATALOG.md.

Done when every baseline concept for this stack is assessed (present, partial, missing) and every failure class from step 2 is either caught by an existing layer or listed as a gap.

## 4. Choose and configure tools

For each gap (missing baseline concept or uncaught failure class), pick a deterministic tool from the concept in CATALOG.md that fits **this stack**. If you do not know the ecosystem's tool for a concept, or compatibility with the language or build version is unclear, research it; whatever stays unclear goes into the plan as "to verify".

Every proposal states:
- the reason: *baseline*, or the failure class with its evidence (commit hashes), or *preventive, no evidence yet*,
- tool and concrete configuration for this repo: which rule or check, where it runs (hook, build task, CI job), how existing violations are handled (fix now, baseline, changed lines only), autofix where the tool offers one,
- the goal in one sentence: what the measure prevents or makes cheaper for the agent,
- the effect, named by mechanism and rated *low*, *medium* or *high*, with the measured or estimated number behind the rating:
  - **tokens:** why fewer tokens: less output read per check (green as one line instead of N lines), fewer repair turns (the failure stops the turn instead of surfacing commits later), less noise read (denied folders), less handwork (generator or script instead of LLM). *High* = saves tokens in every turn or removes whole repair turns; *medium* = saves per check run or per occurrence of a recurring class; *low* = rare or a few hundred tokens,
  - **code quality:** which failure class it stops and at which layer, judged by how often the class occurred (repair commits) and how much a slip costs. *High* = a class with several repairs or fix chains; *medium* = a class seen once or a typical class of the stack; *low* = preventive hygiene,
  - a measure may score on both axes or on only one; say "none" for the other,
- cost: setup effort, duration per run, output when green.

## 5. Write the plan

Phases by effort and benefit:
- **P0** now, each under an hour: quiet check wrapper + Stop hook, deny rules for noise, a single version source, the rule for the most frequent failure class or for a class a tool was proven to catch in step 2, whichever fits in an hour (a class that needs a new kind of test goes to P1).
- **P1** quality in the loop: formatter on edit, compiler/type checks as errors, consistency tests and custom rules for the remaining failure classes, the same checks in CI.
- **P2** deeper: periodic mutation testing, generators instead of LLM handwork, changelog from commits, review subagent with guidelines, dependency updates, branch protection.

Bundle what depends on one decision: without CI, "CI parity", dependency updates and branch protection are one proposal ("add CI"), not three separate gaps.
- **P3** generalisation: uniform verbs (`fmt`, `check`, `test-fast`, `test`) as reusable entry points.

The result is a Markdown report. Its heading is always the English `## Agentic setup`, whatever the report language, so a later run finds and replaces it; the first line below states the date and the skill version. Contents: pipeline per layer as a table (current state, cost, gaps), failure classes with evidence and fix chains, plan P0 to P3 with configurations, an overview table of all measures (measure, goal, tokens low/medium/high with mechanism, quality low/medium/high with failure class, effort, phase), open points to verify, research sources.

Storage:
- The full report always appears in the answer.
- It is saved where the user's instructions keep project knowledge. Without such an instruction, only in a place the user names; the target repo stays unchanged.
- If a report from an earlier run is already there: replace it instead of appending, and carry over points already implemented as done.

Finally: if the repo has uncommitted changes, point out that tooling changes should follow a clean commit. In a dialogue with the user, ask which phase to start with; when started by another session, only report.
