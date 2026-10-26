#!/usr/bin/env bash
# Kartlägger vilka workflows, actions, hemligheter och externa nedladdningar
# som repona i en organisation använder.
#
# Användning:
#   ./kartlagg-workflows.sh                         # rimfrost-repon + .github
#   ./kartlagg-workflows.sh 'rimfrost|^\.github$'   # eget filter (regex på reponamn)
#
# Kräver: gh (inloggad), grep, sed, awk. Läser bara, ändrar ingenting.
# Resultat i katalogen workflow-analys/:
#   repon.txt          repon som undersöktes
#   utan-workflows.txt repon utan .github/workflows
#   filer/<repo>/      kopior av alla workflow-filer
#   uses.tsv           repo, fil, uses-referens (med ref och kommentar)
#   secrets.tsv        repo, fil, hemlighet som refereras
#   externt.tsv        repo, fil, rad med npx/curl/wget/pip/go install
#   sammanfattning.txt sammanställning av ovanstående

set -uo pipefail

ORG="${ORG:-Forsakringskassan}"
FILTER="${1:-rimfrost|^\.github$}"
OUT="${OUT:-workflow-analys}"

rm -rf "$OUT"
mkdir -p "$OUT/filer"
: > "$OUT/uses.tsv"; : > "$OUT/secrets.tsv"; : > "$OUT/externt.tsv"; : > "$OUT/utan-workflows.txt"

gh repo list "$ORG" --no-archived --limit 1000 --json name -q '.[].name' \
  | grep -E -- "$FILTER" | sort > "$OUT/repon.txt"
echo "Undersöker $(wc -l < "$OUT/repon.txt") repon" >&2

while read -r repo; do
  echo "  $repo" >&2
  # gh api skriver ut felsvaret även vid 404, så felkoden måste kontrolleras.
  # Bara filnamn som ser ut som workflow-filer godtas.
  if ! files="$(gh api "repos/$ORG/$repo/contents/.github/workflows" \
      --jq '.[] | select(.type=="file") | .name' 2>/dev/null)"; then
    files=""
  fi
  files="$(grep -E '^[A-Za-z0-9._-]+\.ya?ml$' <<< "$files" || true)"
  if [ -z "$files" ]; then
    echo "$repo" >> "$OUT/utan-workflows.txt"
    continue
  fi

  while read -r f; do
    local_file="$OUT/filer/$repo/$f"
    mkdir -p "$(dirname "$local_file")"
    gh api "repos/$ORG/$repo/contents/.github/workflows/$f" \
      -H 'Accept: application/vnd.github.raw' > "$local_file"

    # Alla uses: (actions och återanvändbara workflows), med ref och ev. kommentar
    grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$local_file" \
      | sed -E 's/^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*//' \
      | awk -v r="$repo" -v f="$f" '{ print r "\t" f "\t" $0 }' >> "$OUT/uses.tsv"

    # Hemligheter som refereras
    grep -oE 'secrets\.[A-Za-z0-9_]+' "$local_file" | sort -u \
      | awk -v r="$repo" -v f="$f" '{ print r "\t" f "\t" $0 }' >> "$OUT/secrets.tsv"

    # Kod som hämtas utifrån i run-steg
    grep -nE '(^|[^A-Za-z])(npx|curl|wget|pip install|go install)([^A-Za-z]|$)' "$local_file" \
      | awk -v r="$repo" -v f="$f" '{ print r "\t" f "\t" $0 }' >> "$OUT/externt.tsv"
  done <<< "$files"
done < "$OUT/repon.txt"

# Referens utan kommentar, t.ex. "actions/checkout@v7"
strip() { cut -f3 | sed -E 's/[[:space:]]+#.*$//; s/^["'\'']//; s/["'\'']$//'; }

{
  echo "== Repon utan workflows"
  cat "$OUT/utan-workflows.txt"
  echo
  echo "== Mest använda referenser (utan version)"
  strip < "$OUT/uses.tsv" | sed -E 's/@.*$//' | sort | uniq -c | sort -rn
  echo
  echo "== Anrop till Forsakringskassan/.github, per ref"
  strip < "$OUT/uses.tsv" | grep '^Forsakringskassan/\.github/' | sort | uniq -c | sort -rn
  echo
  echo "== Tredjepartsactions (inte actions/, github/, Forsakringskassan/ eller lokala ./ och $/)"
  strip < "$OUT/uses.tsv" | grep -vE '^(actions/|github/|Forsakringskassan/|\./|\$/)' | sort | uniq -c | sort -rn
  echo
  echo "== Hemligheter, antal filer som refererar dem"
  cut -f3 "$OUT/secrets.tsv" | sort | uniq -c | sort -rn
  echo
  echo "== Externa nedladdningar i run-steg"
  cut -f1,2,3 "$OUT/externt.tsv"
} > "$OUT/sammanfattning.txt"

echo "Klart. Se $OUT/sammanfattning.txt" >&2
