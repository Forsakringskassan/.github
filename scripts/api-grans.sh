#!/usr/bin/env bash
# Visar hur mycket som återstår av GitHubs API-gränser för den token som gh använder.
#
# Användning:
#   ./api-grans.sh          # visa läget
#   ./api-grans.sh 500      # visa läget, avsluta med felkod 1 om färre än 500 core-anrop återstår
#
# Kräver bara gh (inloggad). I ett workflow: sätt GH_TOKEN.
# Om GITHUB_STEP_SUMMARY finns skrivs tabellen även till körningens sammanfattning.

set -uo pipefail

MIN="${1:-0}"

rows="$(gh api rate_limit --jq '
  .resources | to_entries[]
  | select(.key == "core" or .key == "graphql" or .key == "search" or .key == "code_search")
  | [.key, .value.remaining, .value.limit, (.value.reset | strftime("%Y-%m-%d %H:%M"))]
  | @tsv')" || { echo "Kunde inte hämta API-gränserna" >&2; exit 2; }

printf '%-12s %8s %8s  %s\n' "Resurs" "Kvar" "Gräns" "Återställs (UTC)"
while IFS=$'\t' read -r name remaining limit reset; do
  printf '%-12s %8s %8s  %s\n' "$name" "$remaining" "$limit" "$reset"
done <<< "$rows"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "| Resurs | Kvar | Gräns | Återställs (UTC) |"
    echo "| --- | --- | --- | --- |"
    while IFS=$'\t' read -r name remaining limit reset; do
      echo "| $name | $remaining | $limit | $reset |"
    done <<< "$rows"
  } >> "$GITHUB_STEP_SUMMARY"
fi

core="$(awk -F'\t' '$1 == "core" { print $2 }' <<< "$rows")"
if [ -n "$core" ] && [ "$core" -lt "$MIN" ]; then
  echo "Bara $core core-anrop kvar, kräver minst $MIN" >&2
  exit 1
fi
