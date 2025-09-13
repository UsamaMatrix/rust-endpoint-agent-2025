use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::{env, fs, path::PathBuf};
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AgentConfig {
    pub common: Common,
    pub collectors: Collectors,
    pub output: Output,
    pub networking: Networking,
    pub status: Status,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Common {
    pub instance_id: String,
    pub interval_secs: u64,
    pub max_event_bytes: usize,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Collectors {
    pub top_n_procs: usize,
    pub win_eventlog_channels: Vec<String>,
    pub win_eventlog_rps: u32,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Output {
    pub mode: String,
    pub file_path: Option<PathBuf>,
    pub rotate_bytes: usize,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Networking {
    pub enabled: bool,
    pub endpoint: String,
    pub batch_max_events: usize,
    pub batch_max_bytes: usize,
    pub flush_interval_ms: u64,
    pub queue_dir: PathBuf,
    pub queue_max_bytes: u64,
    pub ca_cert: Option<PathBuf>,
    pub client_cert: Option<PathBuf>,
    pub client_key: Option<PathBuf>,
    pub spki_pin_sha256: Option<String>,
    pub compression: String,
    pub retry_budget: usize,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Status {
    pub port: Option<u16>,
}
impl Default for AgentConfig {
    fn default() -> Self {
        let pd = ProjectDirs::from("io", "REA", "agent")
            .map(|p| p.data_dir().to_path_buf())
            .unwrap_or_else(|| "./data".into());
        Self {
            common: Common {
                instance_id: "rea-default".into(),
                interval_secs: 5,
                max_event_bytes: 128 * 1024,
            },
            collectors: Collectors {
                top_n_procs: 5,
                win_eventlog_channels: vec!["System".into(), "Application".into()],
                win_eventlog_rps: 10,
            },
            output: Output {
                mode: "stdout".into(),
                file_path: Some(pd.join("logs").join("agent.jsonl")),
                rotate_bytes: 10 * 1024 * 1024,
            },
            networking: Networking {
                enabled: false,
                endpoint: "https://127.0.0.1:8443/ingest".into(),
                batch_max_events: 200,
                batch_max_bytes: 512 * 1024,
                flush_interval_ms: 2000,
                queue_dir: pd.join("queue"),
                queue_max_bytes: 50 * 1024 * 1024,
                ca_cert: None,
                client_cert: None,
                client_key: None,
                spki_pin_sha256: None,
                compression: "zstd".into(),
                retry_budget: 8,
            },
            status: Status { port: None },
        }
    }
}
pub fn load_config_with_precedence(cli: Option<&PathBuf>) -> Result<AgentConfig> {
    let mut cfg = AgentConfig::default();
    if let Some(p) = cli {
        if p.exists() {
            let s = fs::read_to_string(p)
                .with_context(|| format!("reading config file {}", p.display()))?;
            let f: AgentConfig = toml::from_str(&s).context("parsing config TOML")?;
            cfg = merge_config(&cfg, &f);
        }
    } else if let Ok(env_path) = env::var("REA_CONFIG") {
        let p: PathBuf = env_path.into();
        if p.exists() {
            let s = fs::read_to_string(&p)
                .with_context(|| format!("reading config file {}", p.display()))?;
            let f: AgentConfig = toml::from_str(&s).context("parsing config TOML")?;
            cfg = merge_config(&cfg, &f);
        }
    }
    if let Ok(v) = env::var("REA_INTERVAL_SECS") {
        if let Ok(n) = v.parse::<u64>() {
            cfg.common.interval_secs = n;
        }
    }
    if let Ok(v) = env::var("REA_ENABLE_NETWORKING") {
        cfg.networking.enabled = v == "1" || v.eq_ignore_ascii_case("true");
    }
    Ok(cfg)
}
pub fn merge_config(a: &AgentConfig, b: &AgentConfig) -> AgentConfig {
    let mut out = a.clone();
    out.common = b.common.clone();
    out.collectors = b.collectors.clone();
    out.output = b.output.clone();
    out.networking = b.networking.clone();
    out.status = b.status.clone();
    out
}
