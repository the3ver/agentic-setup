---
name: analyse-project-setup
description: Assesses a repo's pipeline (edit, end of turn, commit, CI) for the coding agent and proposes deterministic tools, configured for this project, that make agent builds cheaper in tokens and better in code quality. Works for any stack. Produces an assessment and a phased plan; changes nothing.
disable-model-invocation: true
---

# Analyse project setup

Goal: give the coding agent *backpressure*. The pipeline should report failures deterministically and early, cost one line of context when green, and leave mechanical work to scripts. The subject is the **pipeline**, not the code: what runs at which layer, what it costs, and which failure classes slip through it.

[CATALOG.md](CATALOG.md) holds the layer model, the concepts (each with the failure class it catches) and the token techniques. Read it before step 3. Its tool names are examples; choose the tools of the stack you find.

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
- **The check command** an agent would use today. Run it once and measure duration, exit code and output lines: `time <command> 2>&1 | wc -l`. Measure the command as an agent calls it (for example plain `npm test`, `cargo test`, `gradle build`), not with a terser reporter. Run it in the background if it takes longer than 2 minutes, and confirm with `git status` afterwards that it changed no tracked files.

Done when every layer of the model has a current state (present, partial, missing) and the check command has measured numbers.

## 2. Mine the history for failure classes

The repair commits from the inventory are the evidence of what the pipeline lets through. For each repair commit (all of them up to about 30, otherwise the most recent 30 plus the hotspots):
- read its diff (`git show --stat <hash>`, then the relevant hunks),
- name the **failure class** (for example: unformatted code, null/undefined access, wrong layer dependency, forgotten registration or resource, flaky test from fixed waits or real time, version drift, broken CI config, missing translation),
- decide whether a deterministic tool would have caught it, and at which layer.

Search the current code for a pattern only to configure the rule for a failure class you found in the history: count existing occurrences to choose between failing on all, a baseline, or checking only changed lines. Do not scan the code for patterns without evidence from the history.

Further sources for failure classes, if available: the project's docs (README, CLAUDE.md/AGENTS.md, CONTRIBUTING, ADRs), notes systems named in the user's instructions, and a search over past agent sessions (only hits whose `cwd` lies in the repo, excluding runs of this skill). Read an *Agentic setup* report from an earlier run only after this step, so it does not bias the fresh look.

Done when every repair commit you read has a failure class and a verdict (tool could catch it at layer X / needs judgement / one-off).

## 3. Assess the pipeline

For each layer, record:
- **Cost:** duration, output lines when green and when red, noise the agent reads (build output, logs, reports, repo copies).
- **Quality:** which failure classes from step 2 pass this layer undetected.

Answer the check questions in CATALOG.md.

Done when every failure class from step 2 is either caught by an existing layer or listed as a gap.

## 4. Choose and configure tools

For each gap, pick a deterministic tool from the concept in CATALOG.md that fits **this stack**. If you do not know the ecosystem's tool for a concept, or compatibility with the language or build version is unclear, research it; whatever stays unclear goes into the plan as "to verify".

Every proposal states:
- the failure class and its evidence (commit hashes),
- tool and concrete configuration for this repo: which rule or check, where it runs (hook, build task, CI job), how existing violations are handled (fix now, baseline, changed lines only), autofix where the tool offers one,
- cost and benefit: duration per run, output when green, tokens saved or quality gained.

## 5. Write the plan

Phases by effort and benefit:
- **P0** now, each under an hour: quiet check wrapper + Stop hook, deny rules for noise, a single version source, the rule for the most frequent failure class.
- **P1** quality in the loop: formatter on edit, compiler/type checks as errors, consistency tests and custom rules for the remaining failure classes, the same checks in CI.
- **P2** deeper: periodic mutation testing, generators instead of LLM handwork, changelog from commits, review subagent with guidelines, dependency updates, branch protection.
- **P3** generalisation: uniform verbs (`fmt`, `check`, `test-fast`, `test`) as reusable entry points.

The result is a Markdown report headed *Agentic setup (as of <date>)*: pipeline per layer as a table (current state, cost, gaps), failure classes with evidence, plan P0 to P3 with configurations, open points to verify, research sources.

Storage:
- The full report always appears in the answer.
- It is saved where the user's instructions keep project knowledge. Without such an instruction, only in a place the user names; the target repo stays unchanged.
- If a report from an earlier run is already there: replace it instead of appending, and carry over points already implemented as done.

Finally: if the repo has uncommitted changes, point out that tooling changes should follow a clean commit. In a dialogue with the user, ask which phase to start with; when started by another session, only report.
