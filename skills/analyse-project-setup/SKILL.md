---
name: analyse-project-setup
description: Analysiert das Agentic-Coding-Setup eines Repos und schlägt deterministische Werkzeuge vor (Hooks, Linter, Architektur- und Mutationstests, CI), die Qualität sichern und LLM-Tokens sparen. Liefert Bestandsaufnahme und Phasenplan, setzt nichts um.
disable-model-invocation: true
---

# Projekt-Setup analysieren

Ziel: Der Agent soll im Repo *Backpressure* bekommen. Deterministische Sensoren melden Fehler sofort, grüne Läufe kosten eine Zeile Kontext, mechanische Arbeit erledigen Skripte statt das LLM. Ergebnis ist ein Plan, keine Umsetzung.

Das Schichtenmodell, den Werkzeugkatalog je Stack und die Token-Techniken findest du in [CATALOG.md](CATALOG.md). Lies ihn vor Schritt 4.

## 1. Vorwissen holen

- `memory_search` im Vault nach Repo-Name und `agentic-coding-deterministische-tools`. Vorhandene Projektnotiz (`projekte/<repo>.md`) lesen: Architekturregeln, Stolperfallen und Releaseablauf stehen oft nur dort. Einen vorhandenen Abschnitt *Agentic-Setup* aus einem früheren Lauf erst nach Schritt 2 lesen, damit er den frischen Blick nicht vorprägt.
- `search_session_transcripts` nach dem Repo-Namen und nach Stichworten wie `flaky`, `rot`, `vergessen`, `Regression`. Werte nur Treffer aus, deren `cwd` im Repo liegt, und lass die eigene Session sowie frühere Läufe dieses Skills weg (ihr Text enthält die Suchwörter selbst). Wiederkehrende Pannen aus früheren Sessions (rote Builds, vergessene Dateien, Flaky-Tests) sind die besten Kandidaten für neue Regeln.
- Die Zeilen `Panne?` und `ungemergt` aus dem Inventar (Schritt 2) gehören ebenfalls in diese Liste.

Fertig, wenn du eine Liste *Pannen und ungeschriebene Regeln* mit Quelle hast (darf leer sein).

## 2. Inventar ziehen

`inventory.sh` liegt im selben Ordner wie diese SKILL.md (beim Laden als Basisverzeichnis des Skills angegeben):

```bash
bash <skill-ordner>/inventory.sh <repo-pfad>
```

Das Skript liefert Git-Stand, Stack, Tests, Codegröße, gefundene Qualitätswerkzeuge, CI-Workflows, Agenten-Konfiguration (Größe in Tokens, auch importierte Dateien), Versionsstellen und Lärmquellen. Es erkennt Werkzeuge nur an Konfigurationsdateien und Mustern: ein "-" heißt "nicht gefunden", nicht "gibt es sicher nicht".

Danach den schnellsten Prüfbefehl des Repos (Test-Script, `gradlew check` o. ä.) einmal laufen lassen und Dauer, Exit-Code und Ausgabezeilen messen: `time <befehl> 2>&1 | wc -l`. Miss genau den Befehl, den ein Agent heute aufruft (z. B. `npm test` ohne Zusatzflags): Ein knapperer Reporter beschönigt den Ist-Stand und unterschätzt den Gewinn eines Check-Wrappers. Das beantwortet Prüffrage 1. Läuft er länger als 2 Minuten, im Hintergrund starten. Danach mit `git status` sicherstellen, dass der Lauf keine versionierten Dateien verändert hat.

Nimm beides als Faktenbasis und lies nur gezielt nach, wo eine Frage offen bleibt:

- Build-Datei(en), um Plugins und Testkonfiguration zu verstehen.
- Den Haupt-CI-Workflow.
- CLAUDE.md/AGENTS.md und `.claude/settings*.json`.
- 2 bis 3 typische Quell- und Testdateien, um Muster zu erkennen (z. B. "reine Logik-Klassen ohne Framework-Import"). Jedes erkennbare Muster ist eine Architekturregel, die heute nur im Kopf existiert.

Fertig, wenn jede Zeile des Schichtenmodells und jede Zeile der Werkzeugtabelle für diesen Stack (CATALOG.md) einen Ist-Stand hat: vorhanden, teilweise oder fehlt.

## 3. Recherche, nur bei Lücken

Recherchiere im Netz nur, was CATALOG.md für diesen Stack nicht abdeckt: unbekanntes Framework, unklare Kompatibilität eines Werkzeugs mit der verwendeten Sprach- oder Build-Version. Jede Kompatibilitätsfrage, die offen bleibt, wandert als "zu prüfen" in den Plan. Gibt es keine Lücke, steht im Plan "keine Recherche nötig".

## 4. Lückenanalyse

Gehe Schichtenmodell und Werkzeugtabelle Zeile für Zeile durch und halte je Zeile fest: Ist-Stand, Lücke, konkreter Vorschlag mit Werkzeug und Ort (Hook, Build, CI). Prüfe zusätzlich jede Frage aus dem Abschnitt *Prüffragen* in CATALOG.md.

Jeder Vorschlag nennt:
- welche Panne oder welches Risiko er abfängt (aus Schritt 1 oder 2),
- wo er läuft und wie lange er dauert,
- ob er Tokens spart, Qualität sichert oder beides.

Fertig, wenn jede Schicht und jede Prüffrage bewertet ist und jede Panne aus Schritt 1 einem Vorschlag zugeordnet ist.

## 5. Plan schreiben

Phasen nach Aufwand und Nutzen:
- **P0** sofort, je unter einer Stunde: quiet Check-Wrapper (Build und/oder Tests) + Stop-Hook, Deny-Regeln für Lärmquellen, eine Versionsquelle, eine erste Architekturregel.
- **P1** Qualität im Loop: Formatter-Hook, Compiler-Checks, Konsistenztests, Semgrep lokal + CI.
- **P2** tiefer: Mutation Testing periodisch, Generatoren statt LLM-Handarbeit, Changelog aus Commits, Review-Subagent mit Guidelines, Dependabot, Branch-Schutz.
- **P3** Generalisierung: einheitliche Verben (`fmt`, `check`, `test-fast`, `test`), wiederverwendbare Bausteine.

Ablage:
- In der Vault-Projektnotiz `projekte/<repo>.md` den Abschnitt *Agentic-Setup (Stand <Datum>)* anlegen oder, falls vorhanden, ersetzen: Bestandsaufnahme als Tabelle, Plan, offene Prüfpunkte. Bereits umgesetzte Punkte aus dem alten Abschnitt als erledigt übernehmen.
- Neue, stack-übergreifende Erkenntnisse in `topics/agentic-coding-deterministische-tools.md` nachtragen.
- `memory_append_daily` mit einem Satz und Link.
- Vault committen und nach `origin main` pushen.

Antwort: Bestandsaufnahme als Tabelle, Plan P0 bis P3, offene Prüfpunkte, Quellen der Recherche. Hat das Repo uncommittete Änderungen, darauf hinweisen: Tooling-Änderungen erst nach einem sauberen Commit. Im Dialog mit dem Nutzer fragen, mit welcher Phase es losgeht; als gestartete Session nur berichten.
