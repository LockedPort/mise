#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a

API="https://$MEALIE_DOMAIN/api"
AUTH="Authorization: Bearer $MEALIE_API_TOKEN"
JSON="Content-Type: application/json"

# Organizer-IDs einmalig aufloesen: name -> id
declare -A TAG CAT
while read -r id slug; do TAG[$slug]=$id; done < <(
  curl -s -H "$AUTH" "$API/organizers/tags?perPage=100" |
  python3 -c 'import sys,json;[print(i["id"],i["slug"]) for i in json.load(sys.stdin)["items"]]')
while read -r id slug name; do CAT[$slug]="$id|$name"; done < <(
  curl -s -H "$AUTH" "$API/organizers/categories?perPage=100" |
  python3 -c 'import sys,json;[print(i["id"],i["slug"],i["name"]) for i in json.load(sys.stdin)["items"]]')

catjson() {  # $1 = slug
  IFS='|' read -r id name <<< "${CAT[$1]}"
  printf '[{"id":"%s","name":"%s","slug":"%s"}]' "$id" "$name" "$1"
}
tagjson() {  # $@ = slugs
  local out="" s
  for s in "$@"; do
    [ -n "$out" ] && out="$out,"
    out="$out{\"id\":\"${TAG[$s]}\",\"name\":\"$s\",\"slug\":\"$s\"}"
  done
  printf '[%s]' "$out"
}

anlegen() {
  local name="$1" tags="$2" status="$3" rating="$4" cooked="$5" \
        count="$6" season="$7" ing="$8" portion="$9" zutaten="${10}" schritte="${11}"

  local slug
  slug=$(curl -s -X POST -H "$AUTH" -H "$JSON" \
    -d "{\"name\":\"$name\"}" "$API/recipes" | tr -d '"')
  if [ -z "$slug" ] || [ "$slug" = "null" ]; then
    echo "FEHLER beim Anlegen: $name"; return 1
  fi

  local body
  body=$(cat <<EOF
{
  "recipeYield": "$portion Portionen",
  "recipeCategory": $(catjson abendessen),
  "tags": $(tagjson $tags),
  "recipeIngredient": $zutaten,
  "recipeInstructions": $schritte,
  "extras": {
    "status": "$status",
    "rating_10": "$rating",
    "cook_count": "$count",
    "last_cooked": "$cooked",
    "season_tags": "$season",
    "main_ingredient": "$ing",
    "portion_base": "$portion"
  }
}
EOF
)
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X PATCH \
    -H "$AUTH" -H "$JSON" -d "$body" "$API/recipes/$slug")
  printf '%-32s %s  %s\n' "$slug" "$code" "$status"
}

Z1='[{"note":"800 g Ofengemüse gemischt"},{"note":"200 g Feta"},{"note":"3 EL Olivenöl"}]'
S1='[{"text":"Gemüse würfeln, mit Öl mischen."},{"text":"35 Min bei 200 °C, Feta zugeben."}]'
anlegen "Ofen-Gemüse mit Feta" "vegetarisch ofengericht" keeper 8 \
  "$(date -d '21 days ago' +%F)" 4 "9,10,11" kaese 4 "$Z1" "$S1"

Z2='[{"note":"500 g Rinderhack"},{"note":"1 Dose Tomaten"},{"note":"400 g Spaghetti"}]'
S2='[{"text":"Hack anbraten, Tomaten zugeben."},{"text":"45 Min köcheln, Nudeln kochen."}]'
anlegen "Spaghetti Bolognese" "fleisch aufwendig" keeper 9 \
  "$(date -d '4 days ago' +%F)" 12 "" rind 4 "$Z2" "$S2"

Z3='[{"note":"2 Dosen Kichererbsen"},{"note":"400 ml Kokosmilch"},{"note":"2 EL Currypaste"}]'
S3='[{"text":"Currypaste anrösten, Kokosmilch zugeben."},{"text":"Kichererbsen 15 Min ziehen lassen."}]'
anlegen "Kichererbsen-Curry" "vegan schnell one-pot" neu "" "" 0 "" huelsenfruechte 4 "$Z3" "$S3"

Z4='[{"note":"2 Lachsfilets"},{"note":"600 g Kartoffeln"},{"note":"1 Zitrone"}]'
S4='[{"text":"Kartoffeln vorgaren."},{"text":"Mit Lachs 20 Min in den Ofen."}]'
anlegen "Lachs mit Ofenkartoffeln" "fleisch" archiviert 5 \
  "$(date -d '60 days ago' +%F)" 1 "" fisch 2 "$Z4" "$S4"