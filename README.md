# agentic-setup

Claude-Code-Plugin für Agentic Coding mit deterministischen Werkzeugen. Der Agent bekommt *Backpressure*: Formatter, Compiler-Checks, Architektur- und Konsistenztests melden Fehler sofort, grüne Läufe kosten eine Zeile Kontext, mechanische Arbeit erledigen Skripte statt das LLM.

## Inhalt

| Pfad | Zweck |
|---|---|
| `skills/analyse-project-setup/SKILL.md` | Ablauf: Vorwissen, Inventar, Lückenanalyse, Plan P0 bis P3. Nur per `/analyse-project-setup` aufrufbar |
| `skills/analyse-project-setup/inventory.sh` | Deterministische Bestandsaufnahme eines Repos (Git, Stack, Tests, Werkzeuge, CI, Agenten-Konfiguration, Versionen, Lärmquellen) |
| `skills/analyse-project-setup/CATALOG.md` | Schichtenmodell, Werkzeuge je Stack, Semgrep-Ideen, Token-Techniken, Prüffragen |
| `tests/smoke.sh` | Baut ein Wegwerf-Repo mit bekannten Befunden und prüft die Ausgabe von `inventory.sh` |

## Installation

```bash
claude plugin marketplace add the3ver/agentic-setup
claude plugin install agentic-setup@agentic-setup
```

## Entwicklung

```bash
bash tests/smoke.sh
```

Jeder gefundene Fehler im Inventar bekommt zuerst eine Erwartung in `tests/smoke.sh`. Testläufe an echten Repos liefern Berichte; deren Befunde fließen in `SKILL.md`, `CATALOG.md` und `inventory.sh`.

Voraussetzungen: Git Bash oder ein anderes Bash, Git, Python 3 (für JSON).

Der Skill legt Ergebnisse in einem Markdown-Gedächtnis ab, wenn eines per MCP angebunden ist (Tools `memory_search`, `memory_update`, z. B. ein Obsidian-Vault). Ohne Gedächtnis gibt er Bestandsaufnahme und Plan nur in der Antwort aus.
