# 🦀 Rust Endpoint Agent (2025)
![Banner](docs/banner.svg)

**Windows-first, modular telemetry agent with mTLS and enterprise-grade hardening.**
*by [@UsamaMatrix](https://github.com/UsamaMatrix) — Rust Developer & Cyber Security Expert*

<p align="left">
  <a href="https://github.com/UsamaMatrix/rust-endpoint-agent-2025/actions">
    <img alt="CI" src="https://img.shields.io/github/actions/workflow/status/UsamaMatrix/rust-endpoint-agent-2025/ci.yml?label=CI&logo=github">
  </a>
  <img alt="License" src="https://img.shields.io/badge/License-Apache--2.0-blue.svg">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-stable-orange?logo=rust">
  <img alt="Security" src="https://img.shields.io/badge/Security-First-6aa84f?logo=shield">
  <img alt="Platform" src="https://img.shields.io/badge/Windows-first-0078D6?logo=windows">
</p>

> ### Ethics & Authorized Use
>
> • **Professional/authorized environments only.**
> • Transparent operation; **no stealth**.
> • **No self-update**, **no hidden watchdogs**, **no kernel drivers**, **no persistence beyond a documented Windows Service**.
> • Least privilege, strong auth (mTLS), signed releases, and complete audit trails.

---

## ✨ Highlights

* 🧠 **Collectors** (Windows-first; Linux compatible where possible): CPU %, memory, disk per mount, network I/O, process count/top N, OS version/build, uptime, boot time, **Windows Event Log tailer** (channel allowlist, rate-limited).
* 📤 **Outputs**

  * Default: NDJSON → **stdout**.
  * Optional: NDJSON → rotating **file sink** (size/time based).
  * Optional feature `networking`: **HTTPS batches** (rustls) → `https://127.0.0.1:8443/ingest` (test server), with backoff, jitter, retry budget, zstd compression, **bounded disk queue**.
* 🔐 **Security**: rustls, optional **mTLS** client auth, SPKI pinning (opt-in), **no `unsafe`**, JSON size limits, **PII redaction** by default.
* 🛠 **Service (Windows)**: Visible SCM service, installer/uninstaller subcommands, **SCM recovery policy** (no custom watchdogs).
* 🩺 **Health & Metrics**: opt-in 127.0.0.1 status port (`/healthz`, `/metrics` Prometheus) via feature `status`.
* 🧪 **Testing**: Unit tests, property tests, and **integration** (agent → local TLS server).

---

## 🗺️ Architecture

```mermaid
flowchart LR
  subgraph Endpoint[Windows/Linux Endpoint]
    A[Collectors\nCPU/Mem/Disk/Net/Proc/OS/WinEventLog] --> E[Emitter\nNDJSON]
    E -->|stdout| L[Structured Logs]
    E -->|file|  F[Rotating File]
    E -->|mpsc|  Q[(Disk Queue\nbounded)]
    Q -->|flush| N[HTTPS Client\n(rustls + zstd)]
    N -->|POST /ingest| Srv[(Test Receiver\n127.0.0.1:8443)]
    subgraph Status["Optional Status Server (feature=status)"]
      H[/healthz/]
      M[/metrics/ (Prometheus)]
    end
  end

  Admin[Admin/CI] -->|Install| SCM[Windows SCM Service]
  click Srv "server/src/main.rs" "Open server"
```

---

## 📦 Repository Layout (Rust workspace)

```
/agent                          # Endpoint agent (binary crate)
  /src
    main.rs
    lib.rs
    config.rs
    logging.rs
    collectors/
      mod.rs cpu.rs mem.rs disk.rs net.rs proc.rs os.rs win_eventlog.rs
    transport/
      mod.rs client.rs mtls.rs queue.rs
    service/
      mod.rs install.rs uninstall.rs
/server                         # Local HTTPS receiver for tests (binary crate)
/xtask                          # Dev tasks (cert gen, lint/format, sbom helpers)
/configs
  agent.example.toml
  server.example.toml
/.github/workflows/ci.yml
/.gitignore
/LICENSE
/SECURITY.md
/CODE_OF_CONDUCT.md
/CONTRIBUTING.md
/README.md
```

---

## 🚀 Quickstart (Linux dev)

```bash
# 1) Generate self-signed TLS for 127.0.0.1
cargo run -p xtask -- certs --dns 127.0.0.1

# 2) Start local HTTPS receiver (127.0.0.1:8443)
RUST_LOG=server=info cargo run -p server -- configs/certs/server.crt configs/certs/server.key

# 3) In another terminal, run the agent with networking + status
RUST_LOG=info cargo run -p agent --features "networking,status" -- \
  --config configs/agent.example.toml --enable-networking --status_port 9100

# 4) Health & metrics
curl -s http://127.0.0.1:9100/healthz
curl -s http://127.0.0.1:9100/metrics | head
```

---

## 🧪 Demo Media

* Animated SVG (preferred on GitHub): `docs/demo.svg`
  `![demo](docs/demo.svg)`
* Asciinema cast (shareable): `docs/demo.cast`
  Upload: `asciinema upload docs/demo.cast`
* GIF (optional): `docs/demo.gif` (produced via `agg` if available)

Helper scripts:

```bash
# Scripted run (server+agent+curl)
./dev/demo-run.sh

# Record + render (creates docs/demo.cast, and docs/demo.svg if you run svg-term)
./dev/record-demo.sh
# Optional SVG:
svg-term --in docs/demo.cast --out docs/demo.svg --window --width 100 --height 28 --no-cursor
```

---

## ⚙️ Configuration

**Precedence**: `CLI` ➜ `ENV` ➜ `FILE` ➜ built-in defaults.

### Example `configs/agent.example.toml`

```toml
[agent]
node_id = "auto"              # or fixed UUID
batch_interval_ms = 2000
max_event_bytes = 262144      # 256 KiB per NDJSON line
redact_pii = true

[collectors]
top_n_procs = 5
redact_cmdline = true
win_eventlog_channels = ["System", "Application"]
win_eventlog_rps = 10         # rate limit per channel

[logging]
mode = "stdout"               # "stdout" | "file"
file_path = "logs/agent.jsonl"
rotate_bytes = 10485760
rotate_keep = 5

[status]                      # requires --features "status"
enabled = false
port = 9100

[networking]                  # requires --features "networking"
enabled = false
endpoint = "https://127.0.0.1:8443/ingest"
compression = "zstd"          # "none" | "zstd"
retry_budget = 5
backoff_ms = 500..5000        # randomized
queue_dir = "queue"
queue_max_bytes = 104857600   # 100 MiB bounded

[tls]                         # client side (agent→server)
verify = true
ca_file = "configs/certs/server.crt"   # or CA bundle
client_cert = ""              # optional mTLS client cert
client_key = ""               # optional PKCS8 key
spki_pins = []                # ["base64(SPKI)"]
```

### CLI (selected)

```bash
agent --help

# Important toggles:
agent --config <path> --enable-networking --status_port 9100
```

### Environment variables (examples)

```
REA_CONFIG=...                # path to config file
REA_NETWORKING_ENABLED=true
REA_NETWORKING_ENDPOINT=https://127.0.0.1:8443/ingest
REA_TLS_CA_FILE=configs/certs/server.crt
REA_STATUS_PORT=9100
```

---

## 🔒 Security Model & Threat Considerations

* **Transport security**: HTTPS (rustls), optional client mTLS, optional SPKI pinning.
* **Data handling**: JSON schema/size limits, field redaction (e.g. process cmdline) **on by default**.
* **Privilege**: run as standard service account; no `unsafe`; no kernel/drivers.
* **Visibility**: Windows Service listed in Services.msc with clear display name & description.
* **Resource bounds**: bounded disk queue, capped line size, retry budgets, constrained buffers.
* **Auditability**: `tracing` JSON logs, correlation IDs, structured envelopes.
* **Non-goals**: no stealth, no persistence outside SCM, no self-update (use enterprise tools like Intune/SCCM/WSUS).

---

## 🪟 Windows Service (transparent & documented)

Install (PowerShell **Run as Administrator**):

```powershell
# Install (visible in Services.msc)
.\agent.exe service install --display-name "Rust Endpoint Agent" --config "C:\ProgramData\REA\agent.toml"

# Start / Stop
Start-Service "Rust Endpoint Agent"
Stop-Service "Rust Endpoint Agent"

# Recovery policy via SCM (no custom watchdogs)
sc.exe failure "Rust Endpoint Agent" reset= 86400 actions= restart/5000

# Uninstall (clean removal)
.\agent.exe service uninstall
```

> **No hidden persistence**. Only SCM entries created by the installer; nothing else.

---

## 🧰 Kali (VMware) → Windows Cross-Compile

### Install toolchain on Kali

```bash
sudo apt update
sudo apt install -y mingw-w64 gcc-mingw-w64-x86-64 openssl ca-certificates pkg-config zstd
rustup target add x86_64-pc-windows-gnu

mkdir -p .cargo
cat > .cargo/config.toml <<'TOML'
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
TOML

# Build Windows agent.exe
cargo build --release -p agent --target x86_64-pc-windows-gnu
```

### Copy via VMware Shared Folders

```bash
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,auto_unmount
cp target/x86_64-pc-windows-gnu/release/agent.exe /mnt/hgfs/VMShare/
```

### Windows (PowerShell, Admin)

```powershell
# Install service
.\agent.exe service install --config "C:\ProgramData\REA\agent.toml"
Start-Service "Rust Endpoint Agent"

# Verify local status (if enabled)
curl.exe -i http://127.0.0.1:9100/healthz

# Uninstall
Stop-Service "Rust Endpoint Agent"
.\agent.exe service uninstall
```

---

## 🧪 Local HTTPS Test (loopback)

```bash
# Certificates for 127.0.0.1
cargo run -p xtask -- certs --dns 127.0.0.1

# Start test receiver
RUST_LOG=server=info cargo run -p server -- configs/certs/server.crt configs/certs/server.key &

# Agent → POST batches to /ingest
RUST_LOG=info cargo run -p agent --features "networking" -- \
  --config configs/agent.example.toml --enable-networking
```

**mTLS (optional, recommended)**:
You can extend `xtask` to mint a local CA + client cert, configure the server to require client auth, and point the agent at `client_cert`/`client_key` and `ca_file` — then re-run the test.

---

## 📊 Metrics (feature = `status`)

Exposes Prometheus metrics on `127.0.0.1:<port>/metrics`:

* `rea_events_emitted_total`
* `rea_batches_sent_total`
* `rea_batch_errors_total`
* `rea_queue_bytes`

Enable:

```bash
RUST_LOG=info cargo run -p agent --features "status,networking" -- \
  --config configs/agent.example.toml --status_port 9100 --enable-networking
```

---

## 🔁 Config Reload & Cert Rotation

* The agent watches the config file (basic watcher). When toggling `networking.enabled`, the sender is restarted without a full process restart.
* **Certificate rotation**: update files on disk and restart the service (`Stop-Service` / `Start-Service`) or reload config if your cert paths are unchanged.

---

## 🧱 Logging & File Sinks

* Default: structured JSON logs to stdout (controlled via `RUST_LOG`).
* File mode: configure `logging.mode="file"` and `file_path`, with size/time rotation and retention caps.
* All logs include correlation IDs and event kinds for SIEM ingestion.

---

## 🧪 Testing & Quality

Local:

```bash
cargo fmt --all
cargo clippy --all-targets -- -D warnings
cargo test --all --all-features --no-fail-fast

# Optional integration smoke
RUN_SMOKE=1 ./dev/verify.sh
```

CI (GitHub Actions):

* Format, Clippy (deny warnings), tests
* `cargo-audit` and `cargo-deny` (licenses, advisories, bans)
* SBOM (cargo-about)
* Windows GNU cross-build artifact + checksums
* OIDC **provenance attestation**

---

## 🔐 Compliance & Supply Chain

* **License**: Apache-2.0
* **SBOM**: generated in CI (`cargo about generate`)
* **Vulnerability Management**: `cargo audit`, Dependabot
* **Provenance**: GitHub OIDC `actions/attest-build-provenance`
* **Releases**: checksums in `SHA256SUMS` and SBOM attached to GitHub Releases

### Verify release artifacts

```bash
# Download release assets + SHA256SUMS, then:
sha256sum -c SHA256SUMS
```

### Code signing (Windows)

* Sign `agent.exe` with your enterprise certificate (`signtool` or OSS alternatives).
* Publish the signed binary; verify with `Get-AuthenticodeSignature` on Windows.

---

## 🧭 Troubleshooting

* **TLS errors**: SAN must include `127.0.0.1` (the `xtask certs` command does this). Ensure `ca_file` points to trust chain if you enforce verification.
* **Firewall**: allow loopback `8443` for the test server.
* **Clippy failures**: run `cargo clippy -- -D warnings` locally to match CI.
* **Windows DLLs**: GNU target produces largely self-contained binaries. If you switch to MSVC, ensure the VC++ Redistributable is present.
* **Queue growth**: inspect `/metrics`, adjust `queue_max_bytes`, backoff/jitter, and retry budgets.

---

## 🔧 Development

* **MSRV** pinned in workspace; no `unsafe`.
* **Feature flags**:

  * `networking` — HTTPS batches + queue
  * `status` — local health/metrics
  * `win-events` — Windows Event Log tailer (Windows only)
* **Benchmarks** (optional): add Criterion if you need perf baselines.

---

## 🤝 Contributing

* See `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
* We only accept features aligned with **transparent, authorized** endpoint telemetry.
* **No stealth features** will be accepted.

---

## 🛡️ Security

* Report vulnerabilities responsibly via `SECURITY.md`.
* Coordinated disclosure is appreciated.
* We run `cargo-audit` / `cargo-deny` in CI and ship SBOMs on releases.

---

## 🗒️ Non-Goals

* Self-update mechanisms (use enterprise tools like **Intune / SCCM / WSUS**)
* Hidden persistence mechanisms (registry run keys, scheduled tasks, etc.)
* Kernel drivers or user-mode rootkits
* Obfuscation/stealth

---

## 🔚 Appendix: Copy-Paste Checklists

### A) Kali → Windows build & copy

```bash
sudo apt update
sudo apt install -y mingw-w64 gcc-mingw-w64-x86-64 openssl ca-certificates pkg-config zstd
rustup target add x86_64-pc-windows-gnu
mkdir -p .cargo
cat > .cargo/config.toml <<'TOML'
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
TOML

cargo build --release -p agent --target x86_64-pc-windows-gnu

sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,auto_unmount
cp target/x86_64-pc-windows-gnu/release/agent.exe /mnt/hgfs/VMShare/
```

### B) Windows service lifecycle (Admin PowerShell)

```powershell
.\agent.exe service install --display-name "Rust Endpoint Agent" --config "C:\ProgramData\REA\agent.toml"
Start-Service "Rust Endpoint Agent"
# (optional) Recovery:
sc.exe failure "Rust Endpoint Agent" reset= 86400 actions= restart/5000

# Verify (if status enabled)
curl.exe -s http://127.0.0.1:9100/healthz

Stop-Service "Rust Endpoint Agent"
.\agent.exe service uninstall
```

### C) Local HTTPS test

```bash
cargo run -p xtask -- certs --dns 127.0.0.1
RUST_LOG=server=info cargo run -p server -- configs/certs/server.crt configs/certs/server.key &
RUST_LOG=info cargo run -p agent --features networking -- \
  --config configs/agent.example.toml --enable-networking
```

---

> **Branding line for README:**
> **Rust Endpoint Agent (2025)** — Windows-first, modular telemetry agent with mTLS and enterprise-grade hardening.

