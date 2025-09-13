#!/usr/bin/env bash
set -euo pipefail
echo '$ cargo run -p xtask -- certs --dns 127.0.0.1'
cargo run -p xtask -- certs --dns 127.0.0.1
echo
echo '$ RUST_LOG=server=warn cargo run -p server -- configs/certs/server.crt configs/certs/server.key &'
RUST_LOG=server=warn cargo run -p server -- configs/certs/server.crt configs/certs/server.key &
SP=$!
sleep 1
echo
echo '$ RUST_LOG=info cargo run -p agent --features networking,status -- --config configs/agent.example.toml --enable-networking --status_port 9100 &'
RUST_LOG=info cargo run -p agent --features networking,status -- --config configs/agent.example.toml --enable-networking --status_port 9100 &
AP=$!
sleep 4
echo
echo '$ curl -s http://127.0.0.1:9100/healthz'
curl -s http://127.0.0.1:9100/healthz; echo
echo
echo '$ curl -s http://127.0.0.1:9100/metrics | head'
curl -s http://127.0.0.1:9100/metrics | head
kill $AP $SP || true
