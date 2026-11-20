#!/usr/bin/env bash
#: build.sh: placeholder build of the example app.
#:
#: Usage: app/build.sh <out-dir>
#:
#: Copies app/index.html to <out-dir>. Replace this folder with your project
#: and keep the `# deploy-paths:` line of the deploy workflow in sync.
set -euo pipefail
case "${1:-}" in
  -h|--help) sed -n 's/^#: \{0,1\}//p' "$0"; exit 0 ;;
  '') echo "usage: app/build.sh <out-dir>" >&2; exit 2 ;;
esac
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$1"
cp "$here/index.html" "$1/index.html"
echo "built $1/index.html"
