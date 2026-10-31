# Catalog: deterministic tools for agentic coding

## Principles

- CLAUDE.md/AGENTS.md is context, not enforcement. Whatever must always happen belongs in a hook, the build or CI.
- Feedback sensors run inside the agent loop, not only after the commit. Cheap deterministic checks first, expensive LLM reviews later.
- A green run is one line. Show only failures, fail fast (the first failure stops the run).
- Every recurring agent failure becomes a rule (test, Semgrep, ArchUnit), not another line in CLAUDE.md.
- Mechanical work (version, generated resources, changelog draft) is done by a script or generator.
- Coding guidelines go to the review agent, not to the writing agent.
- It works without a tool too: a test that reads source code and checks rules with a regex (guard test) is a cheap first architecture rule. Replace it later with ArchUnit, dependency-cruiser or Semgrep.

## Layer model

| Layer | When | Budget | Typical tools |
|---|---|---|---|
| 1 Edit | PostToolUse hook on the changed file | < 2 s | formatter, syntax/JSON check |
| 2 End of turn | Stop hook | < 60 s | build + fast tests, quiet |
| 3 Commit | commit-msg / pre-commit | < 60 s | Conventional Commits, format check |
| 4 Push/PR | CI | minutes | full suite, compiler checks, Semgrep with SARIF |
| 5 Periodic | CI schedule | long | mutation testing, dependency updates |
| 6 Judgement | review subagent | tokens | guidelines, spec check, only when 1 to 5 are green |
| Cross-cutting | permissions | 0 | deny build/, dist/, logs/, node_modules/, playwright-report/, test-results/, .wrangler/, lockfiles; git guardrails |

Hook mechanics in Claude Code: exit 2 blocks and passes stderr to Claude, exit 1 counts as non-blocking. Keep hooks fast; run targeted tests for small changes.

## Tools per stack

| Purpose | Java/Kotlin (Gradle) | TS/JS (also without a build) | Python |
|---|---|---|---|
| Test runner | JUnit 5 | logic: `node:test` or Vitest; browser: Playwright | pytest |
| Format | Spotless (google-java-format, palantir, ktlint) | Prettier, Biome | ruff format |
| Lint | Error Prone, Checkstyle, PMD, detekt | ESLint, Biome | ruff |
| Types/null | NullAway + JSpecify | TS: `tsc --noEmit`, `strict: true`. Plain JS: `checkJs` or `// @ts-check` + JSDoc, also `tsc --noEmit` | mypy, pyright |
| Architecture | ArchUnit | dependency-cruiser, eslint-plugin-boundaries | import-linter |
| Mutation | PIT (gradle-pitest-plugin) | Stryker (needs Vitest, Jest or `node:test`, not the Playwright runner) | mutmut |
| Dead code | (IDE, some Error Prone checks) | knip | vulture |
| Custom rules | Semgrep | Semgrep | Semgrep |
| Changelog | git-cliff | git-cliff, changesets | git-cliff |

Domain-specific:
- Minecraft/Fabric: Fabric Data Generation instead of handwritten loot, model, recipe and tag JSON. Consistency test: every registration has a blockstate, model, loot table and lang entries in every language.
- Web frontend with Playwright: fixed seeds, mock external services with `page.route`, `forbidOnly: true`, `page.clock` instead of real time, call game logic directly instead of waiting for frames, wait for states instead of `waitForTimeout`, `retries: 0` locally (retries hide flaky tests). If there are only E2E tests, first make pure modules testable with `node:test` or Vitest; only then are mutation testing and fast hooks possible.
- Network games/protocols: consistency test that sender and receiver know the same message types and fields.
- Spring: inject a `Clock` instead of calling `now()`, Spring Modulith verification as an architecture test.

Check before adopting: compatibility with the language version (for example Error Prone and PIT on a new JDK), and build plugins such as Loom that configure the compiler. Check the runtime version in CI against its support status (for example Node versions past EOL).

Experience from a Fabric mod (Java 25, Loom, Gradle 9): ArchUnit 1.4.1, Spotless 8.0.0 with palantir-java-format and Error Prone 2.51.0 (plugin `net.ltgt.errorprone` 5.1.0) work. In Minecraft code Error Prone reports `ReferenceEquality` for intentional identity comparisons of registry objects; disable it. Exempt Mixin `@Inject` methods via `UnusedMethod:ExemptingMethodAnnotations`. Make the formatter switch its own `style:` commit and list it in `.git-blame-ignore-revs`. Tests that check source code by line layout break on the first format run.

## Semgrep rule ideas

- Agent-specific: new `@SuppressWarnings`/`eslint-disable`/`@ts-ignore`/`# noqa`, `@Disabled`/`.skip`/`.only` without a ticket, `TODO` without a ticket, `any` in TS.
- Tests: `Thread.sleep`/`setTimeout`/`waitForTimeout`, tests without assertions, `setAccessible(true)`.
- Conventions: logger instead of `System.out`/`console.log`, no empty `catch`, registrations only in the designated place.
- Lightweight architecture via path filters: `domain/` imports nothing from `infrastructure/`.

## Token techniques

- Whatever a tool can fix itself (formatting, import order), apply automatically in the check wrapper before running checks instead of reporting it to the LLM as a failure.
- Quiet wrapper around build/test: success as one line (`BUILD OK, 132 tests`), on failure only failing tests and trimmed stack traces. Gradle: `-q --console=plain`, test logging only `FAILED`. Vitest/Jest: `--reporter=dot`, `--bail`. Playwright: `--reporter=dot --max-failures=1`, remove `console.log` from tests. Python: `-q -x`.
- Deny rules in `.claude/settings.json` for build output, logs, test reports and dependency folders. Check whether `.claude/` is git-ignored (often via `.git/info/exclude`). Then hooks and deny rules apply only on this machine, not to other clones or cloud sessions. Whether `.claude/settings.json` is versioned is a precondition for P0 and the user's decision. `.claude/worktrees/` holds complete repo copies and belongs on the deny list.
- Keep CLAUDE.md/AGENTS.md lean, imports included: measure bytes, not lines (about 4 bytes per token). Aim for under 10 KB, about 2,500 tokens per session, and no lines over 500 characters. Procedures go into skills, enforcement into hooks, reference material into linked files.
- Generators and scripts for recurring mechanics. The LLM then writes only the inputs, not the outputs.
- Delegate simple subtasks to a cheaper model or a subagent, and verify the result against code and tests.
- Measure the effect on the whole task: a terse context can cause more searching later.

## Check questions

1. Can the agent find out with one command in under 60 s whether everything is green? How many lines does that command print on success?
2. Are there unwritten architecture rules (patterns in packages and classes) that no test checks?
3. Is the version maintained by hand in more than one place, and do all places agree?
4. Does the LLM write files that a generator could produce?
5. Does CI check more than what is usual locally, or less? Does anything run with `continue-on-error`?
6. Are tests hermetic (no clock, no network, no unseeded randomness)? Are there known flaky tests, and do retries hide them?
7. How strong are the tests (mutation score of the core logic)?
8. Which folders create noise when the agent reads them?
9. Are there guardrails against destructive git commands?
10. Are dependency updates automated, is `main` protected, does CI run on PRs and on supported runtime versions?
11. Are there scripts or bridges that execute arbitrary commands from files or the network?
12. Are line endings fixed via `.gitattributes` (important on Windows and with agents that rewrite files)?
13. Are there unused dependencies?
14. Is work sitting unmerged on branches or in worktrees (for example a flaky-test fix that never landed)?
15. Which modules are free of framework, DOM or game access and therefore unit- and mutation-testable right away? Which module blocks the others?

## Sources

- HumanLayer, Context-Efficient Backpressure: https://www.humanlayer.dev/blog/context-efficient-backpressure
- Thoughtworks Radar, Feedback sensors for coding agents: https://www.thoughtworks.com/radar/techniques/feedback-sensors-for-coding-agents
- Dasith, Backpressure in Coding Agent Harnesses: https://dasith.me/2026/06/14/backpressure-in-coding-agent-harnesses/
- Claude Code Hooks Explained: https://blakecrosley.com/blog/claude-code-hooks-explained
- Claude Code Docs, Code Review: https://code.claude.com/docs/en/code-review
