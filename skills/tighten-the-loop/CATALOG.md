# Catalog: deterministic backpressure for coding agents

## Principles

- Instruction files (AGENTS.md, CLAUDE.md, GEMINI.md, rules files) are context, not enforcement. Whatever must always happen belongs in a hook, the build or CI.
- Feedback sensors run inside the agent loop, not only after the commit. Cheap deterministic checks first, expensive LLM reviews later.
- A green run is one line. Show only failures, fail fast (the first failure stops the run).
- Every recurring failure class becomes a rule (check, test, static rule), not another line in an instruction file. The history shows which classes recur.
- Whatever a tool can fix itself (formatting, import order, simple lint fixes), apply automatically before checking instead of reporting it to the LLM.
- Mechanical work (version, generated resources, changelog draft) is done by a script or generator.
- Coding guidelines go to the review agent, not to the writing agent.
- A rule is configured for the project: severity error, not warning; existing violations fixed, baselined, or limited to changed lines; runs at the cheapest layer that still catches the class.

## Layer model

| Layer | When | Budget | Purpose |
|---|---|---|---|
| 1 Edit | after-edit hook of the agent, on the changed file | < 2 s | format, syntax check of that file |
| 2 End of turn | end-of-turn hook of the agent | < 60 s | build + fast tests + static rules, quiet; sends the agent back to work when red |
| 3 Commit | commit-msg / pre-commit | < 60 s | commit message format, staged-file checks |
| 4 Push/PR | CI | minutes | full suite, the same rules as layer 2, security scans, results as annotations (SARIF) |
| 5 Periodic | CI schedule | long | mutation testing, dependency updates, slow scans |
| 6 Judgement | review subagent | tokens | guidelines, spec check, only when 1 to 5 are green |
| Cross-cutting | permissions | 0 | deny reading build output, logs, reports, dependency and repo-copy folders; guardrails against destructive git commands |

Keep layers 1 and 2 fast; skip them when nothing relevant changed (fingerprint of the inputs). Put the logic into one agent-independent script (the check wrapper) and call it from each agent's hook, so the same check serves every agent, git hooks and CI.

### Hooks per agent

Which events implement layers 1 and 2, and how a hook sends the agent back. As of 2026-11; hooks change fast, so check the linked docs before configuring and mark the proposal "to verify" when unsure.

| Agent | Config | Layer 1 (after edit) | Layer 2 (end of turn) | Sends the agent back when red | Read guard (cross-cutting) |
|---|---|---|---|---|---|
| Claude Code | `.claude/settings.json` (`hooks`, `permissions.deny`) | `PostToolUse`, matcher `Edit\|Write` | `Stop` | exit 2, stderr goes to the agent | `permissions.deny` with `Read(...)` |
| Codex CLI | `.codex/hooks.json` or `[hooks.*]` in `config.toml` | `PostToolUse` (matcher on tool name; whether `apply_patch` edits match: to verify) | `Stop` (JSON output required) | JSON `decision` on stdout | sandbox and approval policy, no per-path read deny (to verify) |
| Gemini CLI | `.gemini/settings.json` (`hooks`) | `AfterTool`, matcher regex on tool name | `AfterAgent` | exit 2: retry turn with stderr as feedback | `BeforeTool` hook with exit 2 on read tools |
| Cursor | `.cursor/hooks.json` (`version: 1`) | `afterFileEdit` (informational, cannot talk back to the agent) | `stop` (`followup_message` becomes the next user message; `loop_count` limits loops) | `followup_message` | `beforeReadFile` (to verify) |
| GitHub Copilot (CLI, cloud agent) | `.github/hooks/*.json` | `postToolUse` (can add context for the model) | `sessionEnd` (cleanup only; cannot send the agent back: to verify) | none known at end of turn; use layer 1 or CI | `preToolUse` (to verify) |
| OpenCode | plugin in `.opencode/plugin/` | `tool.execute.after` (reported as not firing in some versions) | `session.idle` (fire-and-forget) | none; the plugin can only report | `tool.execute.before` |
| Windsurf, Cline, Antigravity | to verify | | | | |

Where an agent cannot send itself back at the end of the turn, layer 3 (git pre-commit hook running the check wrapper) and layer 4 (CI) carry the load, and the instruction file (AGENTS.md) tells the agent to run the check command before finishing. That instruction is context, not enforcement: say so in the report.

## Concepts: failure class to tool

Tool names are examples. Pick the equivalent of the stack at hand and research it when unknown.

*Baseline* concepts fit every repo of a stack and are proposed whenever missing. *Evidence* concepts are proposed from repair commits, review findings or visible structure; without such evidence only as "preventive" for the stack's typical failure classes.

| Concept | Kind | Failure class it catches | Signs it is present | Examples |
|---|---|---|---|---|
| Quiet check wrapper | baseline | context flooded by green output; agent misses the one failing line | one command, one line when green | shell script around the build/test command; reporter flags (`-q`, `--reporter=dot`, `--max-failures=1`) |
| Formatter on edit | baseline | style churn in diffs, review noise, "fix formatting" commits | formatter config, hook or CI check | Spotless, Prettier, Biome, ruff format, rustfmt, gofmt, dotnet format, mix format |
| Lint / compiler checks as errors | baseline | known bug patterns, unused code, suspicious constructs | linter config, warnings treated as errors | Error Prone, ESLint, ruff (`ruff check --fix` as autofix), clippy, staticcheck, Roslyn analyzers, Credo |
| Type and null checks | baseline | null/undefined access, wrong types | strict mode in config, type checker in CI | NullAway, `tsc --noEmit` / `checkJs`, mypy, pyright, Kotlin/Rust/Go compilers |
| CI parity | baseline | something passes locally and fails later, or the reverse; no check at all between commits | one CI job calls the same check command as the end-of-turn hook | a workflow running the check wrapper on push and PR; OS matrix when the repo ships OS-specific scripts (`.bat`, `.ps1`) |
| Sensitive data protection | baseline | secrets or personal data read by the agent or committed | deny rules and ignore rules for such files, secret scan | `Read(...)` deny for `config*.json`, `.env*`, data exports; `.gitignore` for real data files; gitleaks in CI |
| Architecture rules | evidence | wrong layer or module dependencies, logic coupled to framework | rule tests or dependency config | ArchUnit, dependency-cruiser, import-linter, go-arch-lint, NetArchTest; a guard test that greps imports |
| Consistency tests | evidence | forgotten registration, resource, translation, protocol field, config key | tests that compare declarations with their counterparts | test that every registered item has its resource files; message types of sender and receiver match |
| Generators | evidence | handwritten derived files drift or break | generator task in the build | data generation, OpenAPI/protobuf codegen, schema-driven code |
| Custom static rules | evidence | project conventions and recurring API misuse, including library traps; agent-specific habits (new suppressions, skipped tests) | rule files in the repo | Semgrep, ast-grep, CodeQL, custom lint rules; for example an ast-grep rule flagging `InstancedMesh` without `frustumCulled = false` |
| Hermetic tests | evidence | flaky tests from fixed waits, real time, network, unseeded randomness; retries that hide them; tests writing screenshots, snapshots or reports into tracked files | rule against sleeps/waits, injected clock, retries 0 locally, test output only in ignored folders | a static rule banning `sleep`/`waitForTimeout` in tests; `Clock`/fake timers; seeded RNG; Playwright `testInfo.outputPath()` |
| Tests for hotspots | evidence | repeated repairs in code that no test covers | tests touching the files with the most repair commits | characterisation tests first, then regular unit tests |
| Mutation testing | evidence | weak tests that pass without checking behaviour (needs tests first) | periodic job with a score | PIT, Stryker, mutmut, cosmic-ray, cargo-mutants, go-mutesting |
| Scene consistency test | evidence | rendering defects unit and smoke tests miss: coplanar faces (z-fighting), geometry crossing the track or floor, objects culled or out of bounds | test that builds the scene headless and checks positions, bounding boxes, layers, normals | Three.js scene built in Node with Vitest; assertions on `Box3`, y-levels, `polygonOffset` on coplanar materials; screenshot comparison only with care for WebGL |
| Browser smoke test | evidence | UI behaviour broken (handlers, wiring, page loads with errors) where unit tests do not reach | one end-to-end test that loads the page and fails on console errors | Playwright, Cypress, Selenium; headless in CI |
| Embedded language in strings | evidence | HTML, JS, SQL or shell inside string literals of another language: escaping rules collide and no tool sees that code | embedded code lives in its own files | move it into separate files that the language's tools check; as an interim step, extract it in a test and run a syntax check (`node --check`, an HTML or SQL parser) |
| Single version source | baseline | version drift between manifest, code, docs | one declared version, others derived or checked | build property read at runtime, generated version files (for example Windows resource info), bump script, consistency test; npm: `npm version patch --no-git-tag-version` keeps `package-lock.json` in step |
| Changelog from commits | baseline | forgotten or inconsistent release notes | tool config, commit message lint | git-cliff, changesets, commitlint |
| Dependency hygiene | baseline | unused or vulnerable dependencies, outdated runtimes | analyzer or update bot | knip, depcheck, cargo-udeps, deptry, Dependabot, Renovate |
| Security scans | baseline | injection, secrets in code, vulnerable dependencies | SAST/SCA job | Semgrep rule packs, CodeQL, gitleaks, dependency audit |
| Line ending policy | baseline | whole-file diffs, broken scripts on another OS | `.gitattributes` | `* text=auto`, `*.sh eol=lf`, `*.bat eol=crlf`, `*.ps1 eol=crlf` (batch labels break with LF) |

Check before adopting: compatibility with the language and build tool version, build plugins that configure the compiler, the support status of CI runtimes.

Field notes:
- Fabric mod (Java 25, Loom, Gradle 9): ArchUnit 1.4.1, Spotless 8.0.0 with palantir-java-format and Error Prone 2.51.0 (plugin `net.ltgt.errorprone` 5.1.0) work. Error Prone reports `ReferenceEquality` for intentional identity comparisons of registry objects; disable it. Exempt Mixin `@Inject` methods via `UnusedMethod:ExemptingMethodAnnotations`.
- Browser game with Playwright only: Stryker cannot use the Playwright runner. First make pure modules testable with `node:test` or Vitest; one module holding DOM state can block all of them.
- Vanilla JS with Three.js: `npx -p typescript tsc --noEmit --allowJs --checkJs` measures type errors without a config; add `@types/three`. Most findings are DOM casts (`getContext` on `HTMLElement`); fix those with JSDoc casts before turning it on as an error. Rendering defects need a scene consistency test, not the browser smoke test.
- Formatter and linter counts: Biome needs `--reporter=summary` (`--max-diagnostics=0` prints only "N not shown"); Prettier `--check` lists files, count them with `wc -l`. Prettier and Biome defaults (double quotes, width 80) produce false churn in code that uses other conventions; measure with the conventions read from the code.
- Python: `uvx ruff check`, `uvx ruff format --check` and `uvx mypy` measure without installing anything. Set ruff's `select` explicitly and `target-version` from the real minimum Python version, otherwise `UP` rules propose syntax the supported version lacks. Without a `pyproject.toml`, propose one for tool configuration only (no packaging needed). `unittest` has `-f` (failfast) but no quiet mode, so the wrapper trims output itself; pytest: `-q -x`. mutmut needs WSL on Windows (to verify); cosmic-ray is an alternative. PyInstaller builds need `--add-data` and `importlib.resources` for files moved out of string literals.
- Any formatter switch: make it its own `style:` commit and list it in `.git-blame-ignore-revs`. Tests that check source code by line layout break on the first format run.

## Token techniques

- Quiet wrapper around build/test: success as one line (`CHECK OK: 132 tests, 12s`), on failure only compiler errors or failing tests with trimmed stack traces. Autofix before checking.
- Skip unchanged states: the end-of-turn hook fingerprints the build inputs and returns immediately when they match the last green run.
- Read guards (table above) for build output, logs, test reports, dependency folders and repo copies that agents create (for example `.claude/worktrees/`; the inventory lists them under noise). Files with secrets or personal data get one too, for privacy rather than tokens. `.gitignore` alone does not stop an agent from reading a file. Check whether the agent's config folder is git-ignored (often via `.git/info/exclude`): then hooks and guards apply only on this machine. Whether to version that config is the user's decision and a precondition for P0.
- Keep the instruction files (CLAUDE.md, AGENTS.md, GEMINI.md, copilot-instructions.md) lean, imports included: measure bytes, not lines (about 4 bytes per token). Aim for under 10 KB, about 2,500 tokens per session. Procedures go into skills, enforcement into hooks, reference material into linked files.
- Generators and scripts for recurring mechanics: the LLM writes only the inputs.
- Delegate simple subtasks to a cheaper model or a subagent, and verify the result against code and tests.
- Measure the effect on the whole task: a terse context can cause more searching later.

## Check questions

1. Can the agent find out with one command in under 60 s whether everything is green? How many lines does that command print on success and on failure?
2. Which failure classes from the history did no layer catch?
3. Is there CI at all? If so, do layer 2 (local) and layer 4 (CI) run the same rules, or can something pass locally and fail in CI (or the reverse)? Does anything run with `continue-on-error`?
4. Are compiler, type and lint findings errors or only warnings?
5. Are there unwritten architecture or consistency rules (visible patterns, past "forgot X" commits) that no check enforces?
6. Does the LLM write files that a generator could produce?
7. Is the version maintained by hand in more than one place, and do all places agree?
8. Are tests hermetic, and do retries hide flaky tests?
9. Do the hotspots (files with the most repair commits) have tests? If so, how strong are they (mutation score)?
10. Which folders create noise when the agent reads or searches them, and are they denied?
11. Do the hooks and deny rules travel with the repo, or are they local only?
12. Is work sitting unmerged on branches or in worktrees?
13. Are there guardrails against destructive git commands?
14. Are there fix chains, where one repair introduced the defect that the next one fixed?
15. Can the agent read or commit files with secrets or personal data?

## Sources

- HumanLayer, Context-Efficient Backpressure: https://www.humanlayer.dev/blog/context-efficient-backpressure
- Thoughtworks Radar, Feedback sensors for coding agents: https://www.thoughtworks.com/radar/techniques/feedback-sensors-for-coding-agents
- Dasith, Backpressure in Coding Agent Harnesses: https://dasith.me/2026/06/14/backpressure-in-coding-agent-harnesses/
- Claude Code Hooks Explained: https://blakecrosley.com/blog/claude-code-hooks-explained
- Claude Code Docs, Code Review: https://code.claude.com/docs/en/code-review
- Codex hooks: https://developers.openai.com/codex/hooks
- Gemini CLI hooks reference: https://geminicli.com/docs/hooks/reference/
- Cursor hooks: https://cursor.com/docs/hooks
- GitHub Copilot hooks reference: https://docs.github.com/en/copilot/reference/hooks-reference
- OpenCode plugins: https://opencode.ai/docs/plugins/
