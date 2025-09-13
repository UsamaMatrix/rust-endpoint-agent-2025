<h1 align="center">🦀 Rust Endpoint Agent (2025)</h1>
<p align="center">
  <b>Windows-first, modular telemetry agent with mTLS and enterprise-grade hardening</b><br/>
  <sub>By <a href="https://github.com/UsamaMatrix">@UsamaMatrix</a> — Developer (Rust) & Cyber Security Expert</sub>
</p>

<p align="center">
  <a href="https://github.com/UsamaMatrix/rust-endpoint-agent-2025/actions"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/UsamaMatrix/rust-endpoint-agent-2025/ci.yml?label=CI&logo=github"></a>
  <img alt="License" src="https://img.shields.io/badge/License-Apache--2.0-blue.svg">
  <img alt="Rust" src="https://img.shields.io/badge/Rust-stable-orange?logo=rust">
  <img alt="Security" src="https://img.shields.io/badge/Security-First-6aa84f?logo=shield">
</p>

> **Ethics & Authorized Use**  
> Professional/authorized environments only. Transparent operation (no stealth), no self-update, no hidden watchdogs, no kernel drivers, no persistence beyond a documented Windows Service. Strong auth (mTLS), signed releases, audit trails.

---

## ✨ Highlights
- 🧠 **Collectors:** CPU, Mem, Disk, Net, Proc(top N), OS(build/version), uptime/boot.  
- 📤 **Outputs:** NDJSON to stdout/file; optional HTTPS batches (rustls) with zstd compression + disk-backed offline queue.  
- 🔐 **Security-first:** no `unsafe`, least privilege, JSON size limits, PII redaction by default.  
- 🏥 **Introspection:** optional `--features status` → `127.0.0.1:/healthz` & `/metrics` (Prometheus).  
- 🪟 **Service (Windows):** visible SCM-managed service; recovery via SCM policies; **no custom watchdogs**.  

---

## 🗺️ Architecture (Mermaid)
```mermaid
flowchart LR
  subgraph Endpoint[Windows/Linux Endpoint]
    A[Collectors\nCPU/Mem/Disk/Net/Proc/OS] --> E[Emitter\nNDJSON Lines]
    E -->|stdout/file| L[Structured Logs]
    E -->|mpsc| Q[(Disk Queue\nbounded)]
    Q -->|batch flush| N[HTTPS Client\n(rustls + zstd)]
    N -->|POST /ingest| Srv[(Test Receiver\n127.0.0.1:8443)]
    subgraph Status["(Optional) Status Server"]
      H[/healthz/]
      M[/metrics/]
    end
  end

  Admin[Admin/CI] -->|Install| SCM[Windows SCM Service]
  click Srv "server/src/main.rs" "Open server"

SH
