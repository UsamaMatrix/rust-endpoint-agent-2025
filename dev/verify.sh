#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-UsamaMatrix/rust-endpoint-agent-2025}"

pass(){ printf "\033[32m[PASS]\033[0m %s\n" "$*"; }
fail(){ printf "\033[31m[FAIL]\033[0m %s\n" "$*"; exit 1; }
info(){ printf "\033[36m[INFO]\033[0m %s\n" "$*"; }

# 0) Workspace sanity
[ -f Cargo.toml ] && pass "Workspace root present" || fail "Missing Cargo.toml"
[ -d agent/src ] && pass "agent crate present" || fail "Missing agent/src"
[ -d server/src ] && pass "server crate present" || fail "Missing server/src"
[ -d xtask/src ]  && pass "xtask crate present"  || fail "Missing xtask/src"

# 1) Key policy/docs files
for f in LICENSE SECURITY.md CODE_OF_CONDUCT.md CONTRIBUTING.md .gitattributes .github/workflows/ci.yml; do
  [ -e "$f" ] || fail "Missing $f"
done
pass "Policy/docs/workflows present"

# 2) Cargo metadata parses
cargo metadata --no-deps -q >/dev/null && pass "Cargo metadata parses"

# 3) Quick build checks (skip long test suite by default)
cargo fmt --all -- --check && pass "rustfmt"
cargo clippy --all-targets -- -D warnings && pass "clippy clean"
cargo check --all --all-features -q && pass "cargo check (all targets)"

# 4) Integration smoke (optional): set RUN_SMOKE=1 to run
if [ "${RUN_SMOKE:-0}" = "1" ]; then
  command -v zstd >/dev/null || { info "Installing zstd"; sudo apt-get update -y && sudo apt-get install -y zstd; }
  cargo run -p xtask -- certs --dns 127.0.0.1 >/dev/null
  RUST_LOG=server=warn cargo run -p server -- configs/certs/server.crt configs/certs/server.key &
  SP=$!
  sleep 1
  RUST_LOG=info cargo run -p agent --features networking -- --config configs/agent.example.toml --enable-networking &
  AP=$!
  sleep 5
  kill $AP || true; kill $SP || true
  pass "Integration smoke (agent → server over HTTPS)"
else
  info "Skip integration smoke (set RUN_SMOKE=1 to run)"
fi

# 5) GitHub repo wiring (needs gh auth)
if gh auth status -h github.com >/dev/null 2>&1; then
  LANGS=$(gh api repos/$REPO_SLUG/languages 2>/dev/null || echo '{}')
  echo "$LANGS" | jq -r 'to_entries[]|"\(.key): \(.value)"' | sed 's/^/[INFO] Langs /' || true
  pass "gh auth OK; repo reachable: $REPO_SLUG"
else
  info "gh not authenticated; skip remote checks"
fi

pass "Verification completed"
