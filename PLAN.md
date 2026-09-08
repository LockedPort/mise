# Plan: mise

Automated weekly meal planning & grocery list generator — n8n + Mealie + Telegram.

> Checkboxen unten sind auf GitHub direkt anklickbar (im Repo, nicht nur in Issues). Ein Klick committet die Änderung automatisch.

Datenmodell, Organizer-IDs und SQL-Abfragen: siehe [SCHEMA.md](SCHEMA.md).
Setup und Architektur: siehe [README.md](README.md).

## Überblick

Jeden Montagmorgen schickt ein Telegram-Bot 10 Rezeptvorschläge (Mischung aus bewährten und neuen), ihr wählt per Button ~5 aus, daraus entsteht automatisch eine auf 2 Personen skalierte Einkaufsliste in deutschen/metrischen Einheiten. Kochanleitungen liegen in Mealie. Sonntags fragt der Bot nach einer Bewertung (1–10), die steuert, was künftig wieder vorgeschlagen wird. Der Bot lässt sich pausieren.

**Lernziel:** Dieses Projekt dient auch dem Aufbau berufsrelevanter Kenntnisse (Docker, self-hosting, SQL/Postgres, REST-APIs, Workflow-Automatisierung) — deshalb bewusst die industrienäheren Optionen.

**Stack:** n8n · Mealie · PostgreSQL · Telegram Bot API · NVIDIA Nemotron 3 Super (OpenRouter) · Caddy · Oracle Cloud VPS

**Deployment:** Drei getrennte Compose-Stacks auf dem VPS — `~/proxy`
(Caddy, besitzt 80/443), `~/n8n` (bestehende n8n-Instanz), `~/mise`
(Postgres + Mealie). Verbunden über zwei Docker-Netze, die **keinem
Stack gehören** und manuell angelegt werden: `edge` (Caddy ↔ n8n,
Caddy ↔ Mealie, zugleich Mealies einziger Weg ins Internet) und
`mise_data` (`internal`, Postgres ↔ Mealie ↔ n8n). Alle drei
Compose-Dateien referenzieren sie als `external: true`.
Siehe README für die `docker network create`-Befehle.

**🔐 Sicherheitsregel:** Repo ist öffentlich. Keine Zugangsdaten/Tokens/Passwörter in getrackten Dateien — alles in `.env` (per `.gitignore` ausgeschlossen), nur `.env.example` mit Platzhaltern wird versioniert. Vor jedem `git add`: `git status` prüfen.

---

## API-Erkenntnisse (Phase 1)

- Rezept anlegen: `POST /api/recipes` mit `{"name": "..."}` gibt nur den
  Slug als String zurück, kein Objekt. Inhalte danach per
  `PATCH /api/recipes/{slug}` nachziehen. Beispiel siehe
  `seed-testrecipes.sh`.
- `recipeCategory` und `tags` brauchen **vollständige Objekte** mit
  `id`, `name` und `slug`. Nur `{"name": ...}` → HTTP 422.
  → IDs in n8n als feste Werte hinterlegen, Liste in SCHEMA.md.
- Umlaute im Slug fallen weg, sie werden **nicht** transliteriert:
  `Frühstück` → `fruhstuck`, `Ofen-Gemüse` → `ofen-gemuse`.
- `extras` akzeptiert beliebige Schlüssel ohne Validierung. Die
  Disziplin muss vom Workflow kommen, nicht von Mealie.
- Leere `extras`-Werte werden als Leerstring gespeichert, nicht als
  NULL → beim Lesen `nullif(value, '')`.
- Zutaten aus `{"note": "250 g rote Linsen"}` bleiben unstrukturiert:
  `quantity`, `unit` und `food` sind `null`, keine Verknüpfung zu den
  2603 Stammdaten-Lebensmitteln. Für die Einkaufsliste (Phase 6) ist
  die Verknüpfung nötig — Mealies Parser-Endpunkt bei Phase 3 klären.
- `recipeYield` ist Freitext; `recipeServings` und `recipeYieldQuantity`
  sind separate numerische Felder, die nicht automatisch daraus befüllt
  werden. Bei Phase 6 prüfen, ob `recipeServings` `portion_base` ersetzt.
- `extras` kommt in `GET /api/recipes` (Liste) **nicht** mit, nur im
  Einzelabruf `GET /api/recipes/{slug}`. Kategorien und Tags dagegen
  schon.
- `queryFilter` greift nicht in `extras` (HTTP 400), `loadFood=true`
  ändert nichts. → Phase 4 liest `extras` direkt aus Postgres,
  Tabelle `api_extras`, Join über **`e.recipee_id = r.id`** (zwei „e",
  Tippfehler im Mealie-Schema), mit dem Read-Only-Nutzer `mise_reader`.
  Geschrieben wird weiterhin ausschließlich über die API.
- Ohne SMTP verschickt Mealie nichts — die E-Mail eines Nutzers ist nur
  Login-Bezeichner. Nutzer werden direkt mit Passwort angelegt.
### Telegram (Phase 2)
- `getUpdates` und Webhook schließen sich aus. Sobald n8n den Trigger
  aktiviert, liefert `getUpdates` nur noch HTTP 409. Chat-IDs deshalb
  **vor** dem ersten Trigger-Start ermitteln.
- n8n hat zwei Webhook-URLs: Test-URL (nur während „Listen for test
  event") und Produktiv-URL (nur bei aktivem Workflow). Ein offener
  Editor-Tab im Lauschmodus legt die Produktivversion still.
- Voraussetzung im n8n-Stack: `WEBHOOK_URL=https://n8n.timkibele.com/`.
  Ohne das baut n8n die Webhook-Adresse aus `localhost:5678` und
  Telegram erreicht sie nicht. Externe Abhängigkeit — n8n ist ein
  eigener Stack.
- Trigger nur auf `message` und `callback_query` stellen, nicht `*`.
- BotFather: jede Stufe eine eigene Nachricht. Bot-Auswahl mit
  `@username`; der Anzeigename wird nie erkannt, Befehl und Argument
  in einer Zeile ebenso wenig.
### Postgres-Init (Phase 2)
- `/docker-entrypoint-initdb.d` führt `.sql`-Dateien **immer** gegen
  `POSTGRES_DB` aus (hier `postgres`). Nur `.sh` kann per `--dbname`
  die Datenbank wählen. Tabellen in `einkauf` deshalb als `.sh`.
- Im Skript `SET ROLE einkauf` vor dem `CREATE TABLE`, sonst gehört die
  Tabelle `postgres` und der n8n-Nutzer darf nicht schreiben.
- Das Init-Verzeichnis läuft nur bei leerem Volume. Bei laufender
  Instanz dieselbe Datei manuell einspielen — das testet sie gleich mit:
  `docker exec -i mise-postgres bash /dev/stdin < postgres/init/xx.sh`
- `timestamptz` kommt in n8n als UTC an. Bei Ausgabe an Telegram
  explizit `toLocaleString('de-DE', {timeZone:'Europe/Berlin'})`,
  sonst zwei Stunden daneben.

---

## Phase 0 – Infrastruktur vorbereiten

- [x] Docker & Docker Compose eingerichtet
- [x] Reverse Proxy + TLS (Caddy, Auto-HTTPS)
- [x] Firewall / OCI-Ingress (80/443 offen)
- [x] VPS-Shape auf 2 OCPU / 12 GB hochgedreht
- [x] Subdomain `mealie.timkibele.com` (DNS-A-Record + Caddyfile-Block)
- [x] Postgres-Container mit persistentem Volume, nicht öffentlich exposed
- [x] Datenbanken `mealie` und `einkauf` angelegt
- [x] Postgres aus n8n im internen Docker-Netz erreichbar
- [x] SSH-Deploy-Key erzeugt und bei GitHub hinterlegt
- [x] Öffentliches Repo `mise` angelegt
- [x] `.gitignore` + `.env.example` vor erstem Commit erstellt
- [x] Erster Commit + Push erfolgreich
- [x] Netze `edge` / `mise_data` aus den Stacks gelöst (`external: true`)
- [x] Port-Mapping `5678:5678` bei n8n entfernt
- [x] Caddy auf `2-alpine` gepinnt, Resolver `127.0.0.11` im Caddyfile

## Phase 1 – Mealie aufsetzen & Datenmodell definieren

- [x] Mealie deployen (Docker, hinter Caddy)
- [x] Admin-Account anlegen (Setup-Wizard)
- [x] Bot-Nutzer anlegen (nicht-Admin, nur `canOrganize`)
- [x] API-Token erzeugen und testen
- [x] `extras`-Schema festlegen → [SCHEMA.md](SCHEMA.md)
- [x] Tags/Kategorien anlegen
- [x] Read-Only-Nutzer `mise_reader` für n8n-Lesezugriffe
- [x] 5 Testrezepte anlegen (`seed-testrecipes.sh`)

## Phase 2 – Telegram-Bot & Steuerung

- [ ] Bot via BotFather anlegen, Token gesichert (in `.env`!)
- [ ] Chat-IDs ermitteln
- [ ] Telegram-Trigger in n8n einrichten
- [ ] Command-Router: `/start`, `/pause`, `/resume`, `/status`
- [ ] `bot_state`-Tabelle in DB `einkauf` anlegen
- [ ] n8n-Credentials: schreibend auf `einkauf`, lesend auf `mealie`
- [ ] Nur eigene Chat-IDs zulassen

## Phase 3 – Rezept-Import per Link (TikTok/Instagram/Web)

- [ ] Link-Erkennung im Command-Router
- [ ] Mealie-URL-Import für klassische Rezeptseiten
- [ ] Caption-Abruf für TikTok/Instagram
- [ ] LLM-Extraktion (Nemotron 3 Super, JSON-Schema via `response_format`)
- [ ] `main_ingredient`-Vokabular aus SCHEMA.md in den Prompt übernehmen
- [ ] Einheiten-Umrechnung in metrisch/deutsch im Prompt
- [ ] Mealies Zutaten-Parser klären (Verknüpfung zu Stammdaten)
- [ ] Rezept in Mealie anlegen (`status=neu`, `extras` befüllt,
      Kategorie `Abendessen`)
- [ ] Bestätigung + Link zurück an Telegram

## Phase 4 – Wochenlauf: Auswahl-Logik

- [ ] Schedule-Trigger Montag 7:00
- [ ] Pause-Check als erster Schritt
- [ ] Rezepte laden: SQL über `mise_reader` (Abfrage in SCHEMA.md)
- [ ] Nur Kategorie `Abendessen` berücksichtigen
- [ ] Pools bilden (`keeper` / `neu`), `archiviert` ausschließen
- [ ] Filter: Wiederholung, Saison, Diversität, Reste
- [ ] Fleisch-Quote (Ziel: zunehmend vegetarisch/vegan)
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
- [ ] Auf 2 Personen skalieren (`portion_base` als Ausgangswert)
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

- **Backup-Skript** für `mise_postgres-data` und `mise_mealie-data`
  (siehe Phase 9).
- **`netfilter-persistent`** speichert bei `save` auch Dockers
  dynamische Regeln mit ein. Führte zu verwaisten DROP-Regeln für
  gelöschte Bridges (`-A PREROUTING -d <ip> ! -i br-<alt> -j DROP`) und
  damit zu stundenlanger Fehlersuche. Klären, ob es neben der
  OCI-Security-List überhaupt gebraucht wird.
- **`n8n_default`** wird weiterhin vom n8n-Stack erzeugt; Caddy hängt
  seit dem Umbau nicht mehr darin. Nur noch Kosmetik.
- **Account der zweiten Person** bewusst noch nicht angelegt — soll erst
  vom fertigen Projekt erfahren. Anlegen: `Home` / `Family`, alle
  Berechtigungen aus.
- Wiederholungsfenster (Wochen bis erneuter Vorschlag): bei Phase 4 festlegen
- „Fertig"-Logik der Auswahl (fixe 5 vs. flexibel): bei Phase 5 entscheiden
- Whisper-Anbieter: erst bei Phase 9 relevant
- **`postgres/init/03-mise-reader.sh`** legt den Nutzer jetzt an, samt
  `ALTER DEFAULT PRIVILEGES` (Mealie legt bei Updates neue Tabellen an).
  Der `CREATE USER`-Teil wurde nie ausgeführt — der Nutzer existierte
  bereits. Bewiesen ist er erst beim nächsten Neuaufsetzen.
- **`can_join_groups` steht noch auf `true`.** Nachholen bei BotFather:
  `/setjoingroups` → `@mise_maus_bot` → `Disable`, je eigene Nachricht.
- **n8n-Attribution** in allen Telegram-Nodes unter Options abschalten
  („Append n8n Attribution"). Ab Phase 5 sonst unter jedem
  Vorschlagsblock.
- **`/start`-Text** hat die Zeilenumbrüche verloren.