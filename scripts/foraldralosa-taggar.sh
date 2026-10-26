#!/usr/bin/env bash
# Hittar versionstaggar utan publicerad GitHub Release, alltså releaser som
# taggades men aldrig byggdes färdigt (det gamla flödet taggar före bygget).
#
# En föräldralös tagg som är högre än senaste release BLOCKERAR nästa release,
# eftersom generic-conventional-release räknar nästa version från högsta taggen.
#
# Användning:
#   ./foraldralosa-taggar.sh               # alla aktiva rimfrost-repon
#   ./foraldralosa-taggar.sh '^rimfrost-'  # eget filter (regex på reponamn)
#
# Kräver: gh (inloggad). Läser bara, ändrar ingenting.
# Resultat i katalogen taggkontroll/:
#   taggar.tsv        repo, tagg, status (blockerar/äldre), datum, release-workflows
#   atgardslista.md   tabell över repon med blockerande taggar, med kommando
#   oversikt.tsv      repo, högsta tagg, senaste release, antal föräldralösa

set -uo pipefail

ORG="${ORG:-Forsakringskassan}"
FILTER="${1:-rimfrost}"
OUT="${OUT:-taggkontroll}"
VERSION_RE='^v?[0-9]+\.[0-9]+\.[0-9]+$'   # bara releaseversioner, inga test- eller förhandsversioner

rm -rf "$OUT"
mkdir -p "$OUT"
printf 'repo\ttagg\tstatus\tdatum\trelease-workflows\n' > "$OUT/taggar.tsv"
printf 'repo\thogsta-tagg\tsenaste-release\tforaldralosa\n' > "$OUT/oversikt.tsv"

# Högsta version av två (sort -V hanterar 1.10.0 > 1.9.0)
max_version() { printf '%s\n%s\n' "$1" "$2" | sed '/^$/d' | sort -V | tail -n 1; }

gh repo list "$ORG" --no-archived --limit 1000 --json name -q '.[].name' \
  | grep -E -- "$FILTER" | sort > "$OUT/repon.txt"
echo "Kontrollerar $(wc -l < "$OUT/repon.txt") repon" >&2

while read -r repo; do
  r="$ORG/$repo"
  echo "  $repo" >&2

  tags="$(gh api "repos/$r/tags" --paginate --jq '.[].name' 2>/dev/null | grep -E "$VERSION_RE" || true)"
  [ -n "$tags" ] || continue

  releases="$(gh release list -R "$r" --limit 1000 --json tagName,isDraft \
    --jq '.[] | select(.isDraft | not) | .tagName' 2>/dev/null || true)"

  highest_tag="$(sort -V <<< "$tags" | tail -n 1)"
  latest_release=""
  if [ -n "$releases" ]; then
    latest_release="$(grep -E "$VERSION_RE" <<< "$releases" | sort -V | tail -n 1 || true)"
  fi

  # Vilka release-workflows repot har, för att se vilket flöde det använder
  workflows="$(gh api "repos/$r/contents/.github/workflows" --jq '.[].name' 2>/dev/null \
    | grep -i release | paste -sd, - || true)"

  orphans=0
  while read -r tag; do
    [ -n "$tag" ] || continue
    grep -qxF "$tag" <<< "$releases" && continue
    orphans=$((orphans + 1))
    if [ -z "$latest_release" ] || { [ "$(max_version "$tag" "$latest_release")" = "$tag" ] && [ "$tag" != "$latest_release" ]; }; then
      status="blockerar"
    else
      status="äldre"
    fi
    date="$(gh api "repos/$r/commits/$tag" --jq '.commit.committer.date' 2>/dev/null || echo '?')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$repo" "$tag" "$status" "$date" "$workflows" >> "$OUT/taggar.tsv"
  done < <(sort -V <<< "$tags")

  printf '%s\t%s\t%s\t%s\n' "$repo" "$highest_tag" "${latest_release:--}" "$orphans" >> "$OUT/oversikt.tsv"
done < "$OUT/repon.txt"

# Åtgärdslista: bara blockerande taggar
{
  echo "# Föräldralösa taggar som blockerar nästa release"
  echo
  echo "| Repo | Tagg | Skapad | Release-workflows | Kommando för att radera |"
  echo "| --- | --- | --- | --- | --- |"
  awk -F'\t' -v org="$ORG" 'NR > 1 && $3 == "blockerar" {
    printf "| %s | %s | %s | %s | `gh api -X DELETE repos/%s/%s/git/refs/tags/%s` |\n", $1, $2, substr($4, 1, 10), $5, org, $1, $2
  }' "$OUT/taggar.tsv"
  echo
  echo "Antal repon med blockerande taggar: $(awk -F'\t' 'NR > 1 && $3 == "blockerar" { print $1 }' "$OUT/taggar.tsv" | sort -u | wc -l)"
  echo "Antal äldre föräldralösa taggar (blockerar inte): $(awk -F'\t' 'NR > 1 && $3 == "äldre"' "$OUT/taggar.tsv" | wc -l)"
} > "$OUT/atgardslista.md"

echo "Klart. Se $OUT/atgardslista.md" >&2
