set -euo pipefail

version=1
root="$(git rev-parse --show-toplevel)"
cd "$root"
PINS="$root/action-lock.json"

jq -e ".version == $version" $PINS &>/dev/null || {
    lockver=$(jq -r ".version" $PINS)
    echo "action-lock file version mismatch at $PINS:"
    echo "expected: $version"
    echo "actual: $lockver"
    exit 1
}

# tldr read jq fetch gh api if it returns tag sha fetch the commit sha
# updates = \n delimited json objs
updates=$(while IFS=$'\t' read -r key repo version; do
  IFS=' ' read -r obj_type sha <<< $(
        gh api "repos/$repo/git/refs/tags/v$version" \
        --jq '.object | "\(.type) \(.sha)"'
    ) || {
    echo "skip: $key ($repo@v$version) — tag not found" >&2; continue
  }
  # annotated tag -> deref to underlying commit
  if [[ "$obj_type" == "tag" ]]; then
    sha=$(gh api "repos/$repo/git/tags/$sha" --jq .object.sha)
  fi
  echo "{\"$key\":\"$sha\"}"
  # filter="$filter | .\"$key\".digest = \"$sha\""
done < <(jq -r '.actions | to_entries[] | "\(.key)\t\(.value.repo)\t\(.value.version)"' "$PINS"))

echo "$updates"
# split, parse each patch, and apply at correct level of json
result=$(jq --arg upd "$updates" '
    reduce ($upd / "\n" | map(fromjson))[] as $p (.;
      ($p | to_entries[0]) as $kv
      | .actions[$kv.key].sha = $kv.value
    )
'  < $PINS)
# atomic write
tmp=$(mktemp "$PINS.XXXXXX")
printf '%s\n' "$result" > "$tmp"
mv "$tmp" "$PINS"
