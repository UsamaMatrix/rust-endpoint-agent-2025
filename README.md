# 🦀 Rust Endpoint Agent (2025)

![Banner](docs/banner.svg)<!-- replace with your own banner; or remove this line -->

<p align="center">
  <img src="https://cdnb.artstation.com/p/assets/images/images/042/806/685/original/terrified-of-ice-cream-ferrisrust-frame.gif" alt="Ferris GIF" width="360">
  &nbsp;&nbsp;&nbsp;
  <img src="https://media4.giphy.com/media/v1.Y2lkPTc5MGI3NjExMHJ1dWhia3UzMmttMmUydjJjcjFqejJxN2o0MGptMmt4dTRjaDNlYyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q/Npdl9kOaKFJHuRCBGx/giphy.gif" alt="Rusty Coding GIF" width="360">
</p>

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
> • **No self-update**, **no hidden watchdogs**, **no kernel drivers**.
> • Persistence only via a documented Windows Service.
> • Least privilege, strong auth (mTLS), signed releases, audit trails.

---

## ✨ Highlights

* 🧠 **Collectors** (Windows-first; Linux compatible where possible): CPU, memory, disks (per mount), network I/O, top-N processes, OS info (name/version/kernel/uptime/boot), optional **Windows Event Log** tailer (rate-limited).
* 📤 **Outputs**

  * NDJSON → **stdout** (default)
  * NDJSON → **file** (size-rotated)
  * Feature `networking`: HTTPS POST batches (rustls) with optional **zstd** + **bounded disk queue**
* 🔐 **Security**: rustls TLS, optional **mTLS**, optional **SPKI pinning**, strictly bounded JSON size, no `unsafe`.
* 🩺 **Health** (feature `status`): `GET /healthz` → `ok`, `GET /metrics` → `rea_up 1`
* 🪟 **Windows Service**: visible in SCM; installer/uninstaller subcommands.

---

## 🧱 Feature Flags

| Feature      | What it does                                 | Default |
| ------------ | -------------------------------------------- | ------- |
| `networking` | HTTPS client (reqwest+rustls), optional zstd | off     |
| `status`     | Local TCP status: `/healthz`, `/metrics`     | off     |
| `win-events` | Windows Event Log tailer hook                | off     |

---

## 🧩 Collectors (current)

| Collector | Fields (examples)                                                                 |
| --------- | --------------------------------------------------------------------------------- |
| CPU       | `global_cpu_percent`, `load_avg_{1,5,15}`                                         |
| Memory    | `total`, `used`, `free` (bytes)                                                   |
| Disk      | per mount: `name`, `total`, `available`                                           |
| Network   | per iface: `name`, `total_received`, `total_transmitted`                          |
| Process   | `total`, `top[] { pid, name, cpu, mem_bytes }`                                    |
| OS        | `name`, `version`, `kernel_version`, `host_name`, `uptime_secs`, `boot_time_secs` |
| WinEvent  | (Windows only, feature `win-events`)                                              |

---

## 🗺️ Architecture

```mermaid
flowchart LR
  subgraph Endpoint["Windows/Linux Endpoint"]
    A[Collectors: CPU/Mem/Disk/Net/Proc/OS/WinEventLog] --> E[Emitter (NDJSON)]
    E --> L[Structured Logs (stdout)]
    E --> F[Rotating File]
    E --> Q[(Disk Queue\nbounded)]
    Q --> N[HTTPS Client\n(rustls + zstd)]
  end

  N -- "POST /ingest" --> Srv[(Test Receiver\n127.0.0.1:8443)]

  subgraph Status["Status Server (feature=status)"]
    H[/GET /healthz/]
    M[/GET /metrics/]
  end

  Admin[Admin/CI] -->|Install| SCM[Windows SCM Service]
```

*(If GitHub still can’t render Mermaid, ensure your repo is public and the code block starts with ` ```mermaid ` exactly.)*

---

## 📦 Repository Layout

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
      mod.rs client.rs queue.rs
    service/
      mod.rs install.rs uninstall.rs
/server                         # Local HTTPS receiver for tests (binary crate)
/xtask                          # Dev helpers (e.g., local certs)
/configs
  agent.example.toml
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
# 1) Generate local TLS for 127.0.0.1 (self-signed)
cargo run -p xtask -- certs --dns 127.0.0.1

# 2) Start the local HTTPS receiver (127.0.0.1:8443)
RUST_LOG=server=info cargo run -p server -- \
  configs/certs/server.crt configs/certs/server.key
# Leave it running (Ctrl+C to stop)

# 3) In another terminal, run the agent with networking + status
RUST_LOG=info cargo run -p agent --features "networking,status" -- \
  --config configs/agent.example.toml \
  --enable-networking \
  --status-port 9100

# 4) Health & metrics
curl -s http://127.0.0.1:9100/healthz
curl -s http://127.0.0.1:9100/metrics
```

### mTLS variant

```bash
# Generate CA + server + client certs (example xtask)
cargo run -p xtask -- mtls --dns 127.0.0.1

# Start server that REQUIRES client auth (pass CA as 3rd arg)
RUST_LOG=server=info cargo run -p server -- \
  configs/certs/server.crt configs/certs/server.key configs/certs/ca.crt

# Ensure agent config points to ca_cert/client_cert/client_key (see example below)
RUST_LOG=info cargo run -p agent --features "networking,status" -- \
  --config configs/agent.example.toml \
  --enable-networking \
  --status-port 9100
```

> The agent runs continuously until you press **Ctrl+C**.

---

## ⚙️ Configuration

**Precedence**: `CLI` ➜ `ENV` ➜ `FILE` ➜ defaults.

```rust
AgentConfig {
  common { instance_id, interval_secs, max_event_bytes },
  collectors { top_n_procs, win_eventlog_channels, win_eventlog_rps },
  output { mode, file_path, rotate_bytes },
  networking {
    enabled, endpoint, batch_max_events, batch_max_bytes,
    flush_interval_ms, queue_dir, queue_max_bytes,
    ca_cert, client_cert, client_key, spki_pin_sha256,
    compression, retry_budget
  },
  status { port }
}
```

### Example: `configs/agent.example.toml`

```toml
[common]
instance_id      = "rea-dev"
interval_secs    = 5
max_event_bytes  = 131072        # 128 KiB

[collectors]
top_n_procs           = 5
win_eventlog_channels = ["System","Application"]
win_eventlog_rps      = 10

[output]
mode         = "stdout"          # or "file"
file_path    = "data/logs/agent.jsonl"
rotate_bytes = 10485760          # 10 MiB

[networking]
enabled           = false         # can be overridden by --enable-networking
endpoint          = "https://127.0.0.1:8443/ingest"
batch_max_events  = 200
batch_max_bytes   = 524288        # 512 KiB
flush_interval_ms = 2000
queue_dir         = "data/queue"
queue_max_bytes   = 52428800      # 50 MiB
ca_cert           = ""            # set to configs/certs/ca.crt for mTLS
client_cert       = ""            # set for mTLS
client_key        = ""            # set for mTLS
spki_pin_sha256   = ""            # optional
compression       = "zstd"        # "zstd" | "none"
retry_budget      = 8

[status]
port = 9100
```

### CLI (selected)

```bash
agent --help

# Important toggles:
agent --config <path> --enable-networking --status-port 9100
```

### Environment variables (examples)

```
REA_CONFIG=...                       # path to config file
REA_ENABLE_NETWORKING=true
REA_INTERVAL_SECS=5
```

---

## 🩺 Health & Metrics (feature = `status`)

* `GET http://127.0.0.1:<port>/healthz` → `ok`
* `GET http://127.0.0.1:<port>/metrics` → `rea_up 1`

---

## 🪟 Windows Service (transparent & documented)

Install (PowerShell **Run as Administrator**):

```powershell
# Install (visible in Services.msc)
.\agent.exe service install --display-name "Rust Endpoint Agent" --config "C:\ProgramData\REA\agent.toml"

# Start / Stop
Start-Service "Rust Endpoint Agent"
Stop-Service  "Rust Endpoint Agent"

# Recovery policy via SCM (no custom watchdogs)
sc.exe failure "Rust Endpoint Agent" reset= 86400 actions= restart/5000

# Uninstall (clean removal)
.\agent.exe service uninstall
```

> **No hidden persistence**. Only SCM entries created by the installer.

---

## 🧰 Kali (VMware) → Windows Cross-Compile

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

# VMware Shared Folders example
sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other,auto_unmount
cp target/x86_64-pc-windows-gnu/release/agent.exe /mnt/hgfs/VMShare/
```

---

## 🔒 Security Model & Non-Goals

| Area       | Stance                                                      |
| ---------- | ----------------------------------------------------------- |
| Transport  | rustls TLS; optional client **mTLS**; optional SPKI pinning |
| Data       | JSON size caps; bounded envelopes                           |
| Privilege  | No `unsafe`; **no** kernel drivers                          |
| Visibility | Windows SCM service with honest display name                |
| Resource   | Bounded disk queue; retry budget                            |
| Non-goals  | Stealth, hidden persistence, self-update, kernel drivers    |

---

## 🧪 Testing & Quality

```bash
cargo fmt --all
cargo clippy --all-targets -- -D warnings
cargo test --all --all-features --no-fail-fast
```

CI (GitHub Actions) recommendations:

* Format + Clippy (deny warnings)
* `cargo-audit` & `cargo-deny`
* SBOM (`cargo-about`)
* Windows cross-build artifact + checksums
* OIDC provenance attestation

---

## 🤝 Contributing

See `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
Only features aligned with **transparent, authorized** endpoint telemetry will be accepted.

---

## 🛡️ Security

Report vulnerabilities via `SECURITY.md`.
We run `cargo-audit`/`cargo-deny` and ship SBOMs on releases.

---

## 📜 License

**Apache-2.0** — see [LICENSE](LICENSE)
