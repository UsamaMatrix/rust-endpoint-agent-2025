#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs

# tools
command -v asciinema >/dev/null || { sudo apt update && sudo apt install -y asciinema; }
command -v go >/dev/null || { sudo apt update && sudo apt install -y golang-go; }

# try to get agg
if ! command -v agg >/dev/null 2>&1; then
  echo "[INFO] installing agg from source…"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  git clone --depth=1 https://github.com/asciinema/agg.git "$tmp/agg"
  (cd "$tmp/agg" && go build ./cmd/agg && sudo install -m0755 agg /usr/local/bin/agg) || true
fi

CAST="docs/demo.cast"
GIF="docs/demo.gif"

# record by running the scripted demo; asciinema will exit cleanly
asciinema rec -y -q -c "bash -lc './dev/demo-run.sh'" "$CAST"

# render GIF if agg is present
if command -v agg >/dev/null 2>&1; then
  agg --font-size 16 --theme dracula --rows 28 --cols 100 --fps 24 "$CAST" "$GIF"
  ls -lh "$CAST" "$GIF"
else
  echo "[WARN] agg not available; kept asciinema cast only:"
  ls -lh "$CAST"
fi
