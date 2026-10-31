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
uvx --from shellcheck-py shellcheck -S error skills/analyse-project-setup/inventory.sh tests/smoke.sh
bash tests/smoke.sh
```

Jeder gefundene Fehler im Inventar bekommt zuerst eine Erwartung in `tests/smoke.sh`. Testläufe an echten Repos liefern Berichte; deren Befunde fließen in `SKILL.md`, `CATALOG.md` und `inventory.sh`.

Voraussetzungen: Git Bash oder ein anderes Bash, Git, Python 3 (für JSON).

Der Skill braucht kein Notizsystem. Er gibt Bestandsaufnahme und Plan in der Antwort aus und ändert das analysierte Repo nicht. Soll der Bericht dauerhaft abgelegt werden, gehört der Ort in die eigenen Anweisungen (z. B. `~/.claude/CLAUDE.md`: "Agentic-Setup-Berichte in `<pfad>` speichern"); der Skill folgt dann diesen Anweisungen.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
