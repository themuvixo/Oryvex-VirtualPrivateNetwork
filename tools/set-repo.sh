#!/usr/bin/env bash
# usage: tools/set-repo.sh <github-user>/<repo>   e.g. tools/set-repo.sh alice/OryvexCore
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <user>/<repo>"; exit 2; }
repo="$1"; lower="$(echo "$repo" | tr 'A-Z' 'a-z')"
cd "$(dirname "$0")/.."
grep -rIl --exclude-dir=quiche --exclude=*.png --exclude-dir=.git -e 'OWNER/OryvexCore' -e 'owner/oryvexcore' . | while read -r f; do
  sed -i.bak -e "s#OWNER/OryvexCore#$repo#g" -e "s#owner/oryvexcore#$lower#g" "$f" && rm -f "$f.bak"
done
echo "links now point at $repo"
