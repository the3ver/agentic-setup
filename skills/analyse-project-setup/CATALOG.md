# Katalog: deterministische Werkzeuge für Agentic Coding

## Grundsätze

- CLAUDE.md/AGENTS.md ist Kontext, keine Durchsetzung. Was immer passieren muss, gehört in Hook, Build oder CI.
- Feedback-Sensoren laufen im Agenten-Loop, nicht erst nach dem Commit. Erst billige deterministische Checks, dann teure LLM-Reviews.
- Grüner Lauf = eine Zeile. Nur Fehler zeigen, fail-fast (erster Fehler bricht ab).
- Jede wiederkehrende Agenten-Panne wird eine Regel (Test, Semgrep, ArchUnit), keine weitere Zeile in CLAUDE.md.
- Mechanische Arbeit (Version, generierte Ressourcen, Changelog-Entwurf) per Skript oder Generator.
- Coding Guidelines bekommt der Review-Agent, nicht der schreibende Agent.
- Ohne Werkzeug geht es auch: ein Test, der Quelltext liest und per Regex Regeln prüft (Wächtertest), ist eine billige erste Architekturregel. Später durch ArchUnit, dependency-cruiser oder Semgrep ersetzen.

## Schichtenmodell

| Schicht | Zeitpunkt | Budget | Typische Werkzeuge |
|---|---|---|---|
| 1 Edit | PostToolUse-Hook auf die geänderte Datei | < 2 s | Formatter, Syntax-/JSON-Check |
| 2 Turn-Ende | Stop-Hook | < 60 s | Build + schnelle Tests, quiet |
| 3 Commit | commit-msg / pre-commit | < 60 s | Conventional Commits, Format-Check |
| 4 Push/PR | CI | Minuten | volle Suite, Compiler-Checks, Semgrep mit SARIF |
| 5 Periodisch | CI schedule | lang | Mutation Testing, Dependency-Updates |
| 6 Urteil | Review-Subagent | Tokens | Guidelines, Spec-Abgleich, nur wenn 1 bis 5 grün |
| Querschnitt | Berechtigungen | 0 | Deny für build/, dist/, logs/, node_modules/, playwright-report/, test-results/, .wrangler/, Lockfiles; Git-Guardrails |

Hook-Mechanik in Claude Code: Exit 2 blockiert und gibt stderr an Claude, Exit 1 gilt als nicht blockierend. Hooks schnell halten, bei kleinen Änderungen gezielte Tests.

## Werkzeuge je Stack

| Zweck | Java/Kotlin (Gradle) | TS/JS (auch ohne Build) | Python |
|---|---|---|---|
| Testrunner | JUnit 5 | Logik: `node:test` oder Vitest; Browser: Playwright | pytest |
| Format | Spotless (google-java-format, palantir, ktlint) | Prettier, Biome | ruff format |
| Lint | Error Prone, Checkstyle, PMD, detekt | ESLint, Biome | ruff |
| Typen/Null | NullAway + JSpecify | TS: `tsc --noEmit`, `strict: true`. Reines JS: `checkJs` bzw. `// @ts-check` + JSDoc, ebenfalls `tsc --noEmit` | mypy, pyright |
| Architektur | ArchUnit | dependency-cruiser, eslint-plugin-boundaries | import-linter |
| Mutation | PIT (gradle-pitest-plugin) | Stryker (braucht Vitest, Jest oder `node:test`, keinen Playwright-Runner) | mutmut |
| Toter Code | (IDE, Error Prone Teilchecks) | knip | vulture |
| Eigene Regeln | Semgrep | Semgrep | Semgrep |
| Changelog | git-cliff | git-cliff, changesets | git-cliff |

Domänenspezifisch:
- Minecraft/Fabric: Fabric Data Generation statt handgeschriebener Loot-, Modell-, Rezept- und Tag-JSONs. Konsistenztest: jede Registrierung hat Blockstate, Modell, Loot, Lang-Einträge in allen Sprachen.
- Web-Frontend mit Playwright: feste Seeds, externe Dienste per `page.route` mocken, `forbidOnly: true`, `page.clock` statt echter Zeit, Spiellogik direkt aufrufen statt Frames abzuwarten, Warten auf Zustände statt `waitForTimeout`, lokal `retries: 0` (Retries verdecken Flaky-Tests). Gibt es nur E2E-Tests, zuerst reine Module mit `node:test` oder Vitest testbar machen; erst dann sind Mutation Testing und schnelle Hooks möglich.
- Netzwerkspiele/Protokolle: Konsistenztest, dass Sender und Empfänger dieselben Nachrichtentypen und Felder kennen.
- Spring: Clock injizieren statt `now()`, Spring Modulith Verifikation als Architekturtest.

Vor Einführung prüfen: Kompatibilität mit der Sprachversion (z. B. Error Prone und PIT mit neuem JDK), Build-Plugins wie Loom, die den Compiler konfigurieren. Laufzeitversion in CI gegen den Support-Status prüfen (z. B. Node-Versionen nach EOL).

Erfahrungen aus mc-3ver (Java 25, Loom, Gradle 9): ArchUnit 1.4.1, Spotless 8.0.0 mit palantir-java-format und Error Prone 2.51.0 (Plugin `net.ltgt.errorprone` 5.1.0) laufen. Error Prone meldet in Minecraft-Code `ReferenceEquality` für absichtliche Identitätsvergleiche von Registry-Objekten; abschalten. `@Inject`-Methoden von Mixins per `UnusedMethod:ExemptingMethodAnnotations` freistellen. Formatter-Umstellung als eigenen `style:`-Commit in `.git-blame-ignore-revs` eintragen. Tests, die Quelltext per Zeilenlayout prüfen, brechen beim ersten Formatieren.

## Semgrep-Regelideen

- Agenten-spezifisch: neue `@SuppressWarnings`/`eslint-disable`/`@ts-ignore`/`# noqa`, `@Disabled`/`.skip`/`.only` ohne Ticket, `TODO` ohne Ticket, `any` in TS.
- Tests: `Thread.sleep`/`setTimeout`/`waitForTimeout`, Tests ohne Assertion, `setAccessible(true)`.
- Konventionen: Logger statt `System.out`/`console.log`, keine leeren `catch`, Registrierungen nur an der vorgesehenen Stelle.
- Leichte Architektur per Pfadfilter: `domain/` importiert nichts aus `infrastructure/`.

## Token-Techniken

- Was ein Werkzeug selbst reparieren kann (Formatierung, Import-Sortierung), im Check-Wrapper vorher automatisch anwenden statt als Fehler ans LLM zu melden.
- Quiet-Wrapper um Build/Test: Erfolg als eine Zeile (`BUILD OK, 132 Tests`), bei Fehler nur fehlschlagende Tests und gekürzte Stacktraces. Gradle: `-q --console=plain`, Test-Logging nur `FAILED`. Vitest/Jest: `--reporter=dot`, `--bail`. Playwright: `--reporter=dot --max-failures=1`, `console.log` in Tests entfernen. Python: `-q -x`.
- Deny-Regeln in `.claude/settings.json` für Build-Ausgaben, Logs, Testreports und Abhängigkeitsordner. Prüfen, ob `.claude/` git-ignoriert ist (oft über `.git/info/exclude`). Dann gelten Hooks und Deny-Regeln nur auf diesem Rechner, nicht für andere Klone oder Cloud-Sessions. Ob `.claude/settings.json` versioniert wird, ist eine Vorbedingung für P0 und eine Entscheidung des Nutzers. `.claude/worktrees/` enthält vollständige Repo-Kopien und gehört in die Deny-Liste.
- CLAUDE.md/AGENTS.md samt Imports schlank halten: Maßstab sind Bytes, nicht Zeilen (ca. 4 Bytes je Token). Richtwert unter 10 KB, also ca. 2.500 Tokens pro Session, keine Zeilen über 500 Zeichen. Abläufe in Skills, Durchsetzung in Hooks, Nachschlagewissen in verlinkte Dateien.
- Generatoren und Skripte für wiederkehrende Mechanik. Das LLM schreibt dann nur noch Eingaben, nicht die Ausgaben.
- Einfache Teilaufgaben delegieren (agy oder Sonnet-Subagent), siehe Vault `topics/ki-delegation-agy`.
- Wirkung am Gesamtergebnis messen: knapper Kontext kann mehr Suchen nach sich ziehen.

## Prüffragen

1. Kann der Agent mit einem Befehl unter 60 s feststellen, ob alles grün ist? Wie viele Zeilen gibt dieser Befehl bei Erfolg aus?
2. Gibt es ungeschriebene Architekturregeln (Muster in Paketen und Klassen), die kein Test prüft?
3. Steht die Version an mehr als einer Stelle von Hand, und stimmen alle Stellen überein?
4. Schreibt das LLM Dateien, die ein Generator erzeugen könnte?
5. Prüft CI mehr als lokal üblich ist, oder weniger? Läuft etwas mit `continue-on-error`?
6. Sind Tests hermetisch (keine Zeit, kein Netz, kein Zufall ohne Seed)? Gibt es bekannte Flaky-Tests, und verdecken Retries sie?
7. Wie stark sind die Tests (Mutation Score der Kernlogik)?
8. Welche Ordner erzeugen Lärm, wenn der Agent sie liest?
9. Gibt es Guardrails gegen destruktive Git-Befehle?
10. Sind Dependency-Updates automatisiert, ist `main` geschützt, läuft CI auf PRs und auf unterstützten Laufzeitversionen?
11. Gibt es Skripte oder Bridges, die beliebige Befehle aus Dateien oder Netz ausführen?
12. Sind Zeilenenden per `.gitattributes` festgelegt (wichtig bei Windows und Agenten, die Dateien neu schreiben)?
13. Gibt es ungenutzte Abhängigkeiten?
14. Liegt Arbeit ungemergt auf Branches oder in Worktrees (z. B. ein Flaky-Fix, der nie gelandet ist)?
15. Welche Module sind frei von Framework-, DOM- oder Spielzugriff und damit sofort unit- und mutationstestbar? Welches Modul blockiert die anderen?

## Quellen

- HumanLayer, Context-Efficient Backpressure: https://www.humanlayer.dev/blog/context-efficient-backpressure
- Thoughtworks Radar, Feedback sensors for coding agents: https://www.thoughtworks.com/de/radar/techniques/feedback-sensors-for-coding-agents
- Dasith, Backpressure in Coding Agent Harnesses: https://dasith.me/2026/06/14/backpressure-in-coding-agent-harnesses/
- Claude Code Hooks Explained: https://blakecrosley.com/blog/claude-code-hooks-explained
- Claude Code Docs, Code Review: https://code.claude.com/docs/en/code-review
