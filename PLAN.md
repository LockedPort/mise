# Plan: mise

Automated weekly meal planning & grocery list generator — n8n + Mealie + Telegram.

> Checkboxen unten sind auf GitHub direkt anklickbar (im Repo, nicht nur in Issues). Ein Klick committet die Änderung automatisch.

## Überblick

Jeden Montagmorgen schickt ein Telegram-Bot 10 Rezeptvorschläge (Mischung aus bewährten und neuen), ihr wählt per Button ~5 aus, daraus entsteht automatisch eine auf 2 Personen skalierte Einkaufsliste in deutschen/metrischen Einheiten. Kochanleitungen liegen in Mealie. Sonntags fragt der Bot nach einer Bewertung (1–10), die steuert, was künftig wieder vorgeschlagen wird. Der Bot lässt sich pausieren.

**Lernziel:** Dieses Projekt dient auch dem Aufbau berufsrelevanter Kenntnisse (Docker, self-hosting, SQL/Postgres, REST-APIs, Workflow-Automatisierung) — deshalb bewusst die industrienäheren Optionen.

**Stack:** n8n · Mealie · PostgreSQL · Telegram Bot API · NVIDIA Nemotron 3 Super (OpenRouter) · Caddy · Oracle Cloud VPS

**🔐 Sicherheitsregel:** Repo ist öffentlich. Keine Zugangsdaten/Tokens/Passwörter in getrackten Dateien — alles in `.env` (per `.gitignore` ausgeschlossen), nur `.env.example` mit Platzhaltern wird versioniert. Vor jedem `git add`: `git status` prüfen.

---

## Phase 0 – Infrastruktur vorbereiten

- [x] Docker & Docker Compose eingerichtet
- [x] Reverse Proxy + TLS (Caddy, Auto-HTTPS)
- [x] Firewall / OCI-Ingress (80/443 offen)
- [x] VPS-Shape auf 2 OCPU / 12 GB hochgedreht
- [ ] Subdomain `mealie.timkibele.com` (DNS-A-Record + Caddyfile-Block)
- [ ] Postgres-Container mit persistentem Volume, nicht öffentlich exposed
- [ ] Datenbanken `mealie` und `einkauf` angelegt
- [ ] Postgres aus n8n im internen Docker-Netz erreichbar
- [x] SSH-Deploy-Key erzeugt und bei GitHub hinterlegt
- [x] Öffentliches Repo `mise` angelegt
- [x] `.gitignore` + `.env.example` vor erstem Commit erstellt
- [x] Erster Commit + Push erfolgreich

## Phase 1 – Mealie aufsetzen & Datenmodell definieren

- [ ] Mealie deployen (Docker, hinter Caddy)
- [ ] Admin-Account + beide Nutzer anlegen
- [ ] API-Token erzeugen und testen
- [ ] `extras`-Schema festlegen (rating_10, status, cook_count, last_cooked, season_tags, main_ingredient, portion_base)
- [ ] Tags/Kategorien anlegen
- [ ] 3–5 Testrezepte anlegen (teils `neu`, teils `keeper`)

## Phase 2 – Telegram-Bot & Steuerung

- [ ] Bot via BotFather anlegen, Token gesichert (in `.env`!)
- [ ] Chat-IDs ermitteln
- [ ] Telegram-Trigger in n8n einrichten
- [ ] Command-Router: `/start`, `/pause`, `/resume`, `/status`
- [ ] `bot_state`-Tabelle in Postgres anlegen
- [ ] Nur eigene Chat-IDs zulassen

## Phase 3 – Rezept-Import per Link (TikTok/Instagram/Web)

- [ ] Link-Erkennung im Command-Router
- [ ] Mealie-URL-Import für klassische Rezeptseiten
- [ ] Caption-Abruf für TikTok/Instagram
- [ ] LLM-Extraktion (Nemotron 3 Super, JSON-Schema via `response_format`)
- [ ] Einheiten-Umrechnung in metrisch/deutsch im Prompt
- [ ] Rezept in Mealie anlegen (`status=neu`, `extras` befüllt)
- [ ] Bestätigung + Link zurück an Telegram

## Phase 4 – Wochenlauf: Auswahl-Logik

- [ ] Schedule-Trigger Montag 7:00
- [ ] Pause-Check als erster Schritt
- [ ] Rezepte aus Mealie laden
- [ ] Pools bilden (`keeper` / `neu`)
- [ ] Filter: Wiederholung, Saison, Diversität, Reste
- [ ] Mischung ziehen (bis 5 `keeper` + auffüllen mit `neu`)
- [ ] Ergebnis in `weekly_run` speichern

## Phase 5 – Vorschläge senden & Auswahl einsammeln

- [ ] Nachricht mit 10 Rezepten formatieren
- [ ] Inline-Buttons je Rezept (nehmen / skip)
- [ ] Auswahl-Handling + „Fertig"-Button
- [ ] Mealie-Wochenplan schreiben
- [ ] Bestätigung an Telegram

## Phase 6 – Einkaufsliste generieren

- [ ] Zutaten der gewählten Rezepte sammeln
- [ ] Auf 2 Personen skalieren
- [ ] Einheiten normalisieren/umrechnen
- [ ] Deduplizieren & zusammenfassen
- [ ] In Mealie-Einkaufsliste schreiben

## Phase 7 – Bewertungs-Loop

- [ ] Schedule-Trigger Sonntag 18:00 (+ Pause-Check)
- [ ] Nachfrage je Rezept mit 1–10-Buttons
- [ ] Callback → `extras` schreiben (`rating_10`, `cook_count`, `last_cooked`)
- [ ] Status ableiten (`keeper` ab ≥7 / `archiviert` <7)
- [ ] Bestätigung an Telegram

## Phase 8 – Intelligenz-Filter ausbauen

- [ ] Saisonalität feinjustieren
- [ ] Restevermeidung
- [ ] Diversitäts-Filter
- [ ] Optional: Scoring statt harter Filter

## Phase 9 – Ausbaustufen (optional)

- [ ] Erweiterte Pause (`/pause 3w` mit Auto-Resume)
- [ ] Audio-Transkription für TikTok (Whisper)
- [ ] Vorrats-Abgleich dauerhaft einbauen
- [ ] Mengen-Feinschliff (Gebindegrößen, Grundzutaten)
- [ ] Backups für Mealie-Daten und Postgres

---

## Offene Detailpunkte

- Genaue Mealie-Feldnamen/Endpunkte: bei Phase 1 klären
- Wiederholungsfenster (Wochen bis erneuter Vorschlag): bei Phase 4 festlegen
- „Fertig"-Logik der Auswahl (fixe 5 vs. flexibel): bei Phase 5 entscheiden
- Whisper-Anbieter: erst bei Phase 9 relevant
