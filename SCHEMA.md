# Datenmodell

## extras (pro Rezept)

Alle Werte als String. Alle Schlüssel immer schreiben, auch leer —
ein fehlender Schlüssel verhält sich in JS anders als ein leerer.

| Schlüssel | Format | Beispiel | Leer bedeutet |
|---|---|---|---|
| `status` | `neu` \| `keeper` \| `archiviert` | `keeper` | nie leer |
| `rating_10` | `"1"`–`"10"` | `"8"` | noch nie bewertet |
| `cook_count` | Ganzzahl | `"3"` | Start: `"0"` |
| `last_cooked` | `YYYY-MM-DD` | `"2026-08-31"` | noch nie gekocht |
| `season_tags` | Monatszahlen, kommagetrennt | `"6,7,8,9"` | ganzjährig |
| `main_ingredient` | ein Wort, klein, ohne Umlaute | `haehnchen` | unbekannt |
| `portion_base` | Ganzzahl | `"4"` | unbekannt |

Mealie speichert leere Werte als Leerstring, **nicht** als NULL.
Beim Lesen per SQL deshalb `nullif(value, '')` verwenden.

### main_ingredient — kontrolliertes Vokabular

Proteinquelle, nicht Ernährungsform. Steuert den Diversitäts-Filter
(nicht zweimal dasselbe pro Woche). Nur diese Werte:

`haehnchen` `rind` `schwein` `fisch` `meeresfruechte` `ei` `kaese`
`huelsenfruechte` `tofu` `seitan` `tempeh` `gemuese`

Diese Liste wörtlich in den LLM-Prompt (Phase 3) übernehmen.

Bewusst fein aufgelöst statt gruppiert: Der Filter soll „nicht zweimal
dasselbe Protein" durchsetzen. Würde man alles Tierische zu einem Wert
zusammenfassen, sperrte ein Hähnchengericht auch Fisch und Rind für die
Woche, während drei `gemuese`-Gerichte nebeneinander stehen dürften.
Wie oft Fleisch vorkommt, steuert nicht dieses Feld, sondern eine
Quotenregel in Phase 4 (z. B. „höchstens ein `fleisch`-Tag pro Woche").

### status

- `neu` — importiert, noch nie gekocht
- `keeper` — bewertet mit ≥ 7
- `archiviert` — bewertet mit < 7, wird nicht mehr vorgeschlagen

### season_tags

Monatszahlen statt Jahreszeitennamen, damit der Filter in Phase 4 nur
prüfen muss, ob der aktuelle Monat in der Liste steht. Leer heißt
ganzjährig — das ist der häufigste Fall.

## Tags

- Ernährungsform: `vegan` `vegetarisch` `fleisch`
- Aufwand: `schnell` (< 30 min) `aufwendig`
- Kontext: `resteverwertung` `mealprep` `ofengericht` `one-pot` `suppe`

## Kategorien

`Abendessen` `Beilage`

Nur `Abendessen` wird im Wochenlauf (Phase 4) gezogen. Rezepte ohne
diese Kategorie bleiben in Mealie als Rezeptbuch nutzbar, tauchen aber
nie im Montags-Vorschlag auf. Der LLM-Prompt in Phase 3 setzt die
Kategorie beim Import mit.

## Organizer-IDs

`recipeCategory` und `tags` brauchen beim Schreiben vollständige Objekte
mit `id`, `name` und `slug` — nur `{"name": ...}` gibt HTTP 422. Damit
n8n die IDs nicht bei jedem Lauf auflösen muss, hier der aktuelle Stand.

**Installationsspezifisch.** Nach einem Neuaufsetzen neu ermitteln:

```bash
curl -s -H "Authorization: Bearer $MEALIE_API_TOKEN" \
  "https://$MEALIE_DOMAIN/api/organizers/tags?perPage=100" \
  | python3 -c 'import sys,json;[print(i["id"],i["slug"]) for i in json.load(sys.stdin)["items"]]'
```

Kategorien:

| Slug | Name | ID |
|---|---|---|
| `abendessen` | Abendessen | `c35e10a8-22af-4c98-91f0-dd7468ca413a` |
| `beilage` | Beilage | `4c9e6fc3-9a60-4f8e-96c4-becdd49df799` |

Tags:

| Slug | ID |
|---|---|
| `vegan` | `fc6500d8-dfe7-4d38-af6c-ca195be94c6a` |
| `vegetarisch` | `ec2b7a28-b9ac-4e1a-92a6-bc7fa82d7be8` |
| `fleisch` | `6b3fed2e-024f-4c8c-9301-6e8f80d3ea87` |
| `schnell` | `661d7577-98c1-4c0e-b9ed-fdb091ebc39a` |
| `aufwendig` | `a10e0562-6335-482b-9813-de8545ff6d9d` |
| `resteverwertung` | `411b42e7-a3c3-4af5-9605-2ad7e71e0dda` |
| `mealprep` | `706b5364-d75d-4736-8512-70d0e28a1ae5` |
| `ofengericht` | `854a89fc-9903-4bbc-a061-dfe7b7d1aba9` |
| `one-pot` | `b2f46432-f0d1-4246-a5ca-51dba9f795ce` |
| `suppe` | `bcf51cbf-3899-4983-a32e-9883a83453d3` |

Gruppe `Home`: `9194a7bf-5fe1-4e31-ba7c-682c4050118a`
Haushalt `Family`: `6a60fec9-369f-4a49-be17-0f474f6bc2db`

## extras aus Postgres lesen

`extras` kommt in der Rezept-Liste der API **nicht** mit, und
`queryFilter` greift nicht hinein (siehe PLAN.md, API-Erkenntnisse).
Phase 4 liest deshalb direkt aus Postgres — lesend, mit dem Nutzer
`mise_reader`. Geschrieben wird ausschließlich über die API, damit
Mealie seine eigene Konsistenz behält.

Tabelle `api_extras`, eine Zeile pro Schlüssel. Die Join-Spalte heißt
`recipee_id` — **zwei „e"**, Tippfehler im Mealie-Schema.

```sql
select r.slug, r.name,
       max(case when e.key_name='status'          then e.value end)              as status,
       max(case when e.key_name='rating_10'       then nullif(e.value,'') end)   as rating,
       max(case when e.key_name='last_cooked'     then nullif(e.value,'') end)   as last_cooked,
       max(case when e.key_name='cook_count'      then e.value end)              as cook_count,
       max(case when e.key_name='main_ingredient' then e.value end)              as main_ingredient,
       max(case when e.key_name='season_tags'     then e.value end)              as season_tags
from recipes r
left join api_extras e on e.recipee_id = r.id
group by r.slug, r.name;
```

## Nicht in extras

Ernährungsform läuft über Tags, nicht über `main_ingredient` — ein
Tofu-Gericht ist auch vegan, beides muss gleichzeitig abbildbar sein.

Portionsangaben: Mealies `recipeYield` ist Freitext („4 Portionen"),
deshalb zusätzlich `portion_base` als maschinenlesbare Zahl. Mealie hat
daneben die numerischen Felder `recipeServings` und
`recipeYieldQuantity`, die aber nicht automatisch aus `recipeYield`
befüllt werden — bei Phase 6 prüfen, ob eines davon `portion_base`
ersetzen kann.