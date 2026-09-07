# Datenmodell

## extras (pro Rezept)

Alle Werte als String. Alle Schlüssel immer schreiben, auch leer —
ein fehlender Schlüssel verhält sich anders als ein leerer.

| Schlüssel | Format | Beispiel | Leer bedeutet |
|---|---|---|---|
| `status` | `neu` \| `keeper` \| `archiviert` | `keeper` | nie leer |
| `rating_10` | `"1"`–`"10"` | `"8"` | noch nie bewertet |
| `cook_count` | Ganzzahl | `"3"` | Start: `"0"` |
| `last_cooked` | `YYYY-MM-DD` | `"2026-08-31"` | noch nie gekocht |
| `season_tags` | Monatszahlen, kommagetrennt | `"6,7,8,9"` | ganzjährig |
| `main_ingredient` | ein Wort, klein, ohne Umlaute | `haehnchen` | unbekannt |
| `portion_base` | Ganzzahl | `"4"` | unbekannt |

### main_ingredient — kontrolliertes Vokabular

Proteinquelle, nicht Ernährungsform. Steuert den Diversitäts-Filter
(nicht zweimal dasselbe pro Woche). Nur diese Werte:

`haehnchen` `rind` `schwein` `fisch` `meeresfruechte` `ei` `kaese`
`huelsenfruechte` `tofu` `seitan` `tempeh` `gemuese`

Diese Liste wörtlich in den LLM-Prompt (Phase 3) übernehmen.

### status

- `neu` — importiert, noch nie gekocht
- `keeper` — bewertet mit ≥ 7
- `archiviert` — bewertet mit < 7, wird nicht mehr vorgeschlagen

## Tags

Ernährungsform: `vegan` `vegetarisch` `fleisch`
Aufwand: `schnell` (< 30 min) `aufwendig`
Kontext: `resteverwertung` `mealprep` `ofengericht` `one-pot`

## Kategorien

`Hauptgericht` `Beilage` `Frühstück` `Suppe` `Dessert`

## Nicht in extras

Ernährungsform läuft über Tags, nicht über `main_ingredient` —
ein Tofu-Gericht ist auch vegan, beides gleichzeitig abbildbar.
Portionsangaben: Mealies `recipeYield` ist Freitext, deshalb
zusätzlich `portion_base` als maschinenlesbare Zahl.