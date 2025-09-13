#!/usr/bin/env bash
set -euo pipefail
mkdir -p .cargo .github/workflows configs agent/src/collectors agent/src/service agent/src/transport server/src xtask/src
printf '%s\n' '/target' '**/*.rs.bk' '**/*.swp' '.DS_Store' '.idea' '.vscode' '*.pdb' '*.obj' '*.dll' '*.exe' '*.log' '/configs/*.pem' '/configs/*.key' '/configs/*.crt' '/configs/certs/' > .gitignore
cat > .cargo/config.toml <<'TOML'
[build]
rustflags = ["-Dwarnings"]
TOML
cat > Cargo.toml <<'TOML'
[workspace]
members = ["agent", "server", "xtask"]
resolver = "2"
[workspace.package]
edition = "2021"
license = "Apache-2.0"
authors = ["Rust Endpoint Agent maintainers"]
rust-version = "1.75"
[workspace.dependencies]
anyhow = "1.0"
thiserror = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
toml = "0.8"
clap = { version = "4.5", features = ["derive", "env"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt", "json"] }
tracing-appender = "0.2"
sysinfo = { version = "0.30", features = ["serde"] }
time = { version = "0.3", features = ["formatting", "macros", "serde-human-readable"] }
directories = "5.0"
rand = "0.8"
zstd = "0.13"
tokio = { version = "1.39", features = ["rt-multi-thread", "macros", "fs", "io-util", "signal", "time", "sync", "net"] }
notify = "6.1"
uuid = { version = "1.10", features = ["v4", "serde"] }
bytes = "1.6"
hyper = { version = "1.4", features = ["http1", "server", "client"] }
http = "1.1"
hyper-util = { version = "0.1", features = ["client", "server", "http1", "tokio"] }
rustls = { version = "0.23", default-features = false, features = ["ring", "logging"] }
rustls-pemfile = "2.1"
tokio-rustls = "0.26"
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls", "gzip", "json", "http2", "zstd"] }
prometheus = "0.13"
proptest = "1.5"
[target.'cfg(windows)'.workspace.dependencies]
windows-service = "0.6"
windows-sys = { version = "0.59", features = [
  "Win32_System_EventLog","Win32_System_ServiceManagement","Win32_System_SystemServices","Win32_Foundation"
] }
TOML
cat > agent/Cargo.toml <<'TOML'
[package]
name = "agent"
version = "0.1.0"
edition = "2021"
rust-version = "1.75"
license = "Apache-2.0"
description = "Rust Endpoint Agent (2025) — Windows-first, modular telemetry agent with mTLS and enterprise-grade hardening."
[features]
default = []
networking = ["reqwest", "zstd"]
status = ["prometheus", "hyper", "hyper-util"]
win-events = []
[dependencies]
anyhow = { workspace = true }
thiserror = { workspace = true }
serde = { workspace = true }
serde_json = { workspace = true }
toml = { workspace = true }
clap = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
tracing-appender = { workspace = true }
sysinfo = { workspace = true }
time = { workspace = true }
directories = { workspace = true }
rand = { workspace = true }
uuid = { workspace = true }
bytes = { workspace = true }
tokio = { workspace = true }
notify = { workspace = true }
zstd = { workspace = true, optional = true }
reqwest = { workspace = true, optional = true, default-features = false, features = ["rustls-tls","gzip","json","http2","zstd"] }
prometheus = { workspace = true, optional = true }
hyper = { workspace = true, optional = true }
hyper-util = { workspace = true, optional = true }
http = { workspace = true }
rustls = { workspace = true }
rustls-pemfile = { workspace = true }
tokio-rustls = { workspace = true }
[target.'cfg(windows)'.dependencies]
windows-service = { workspace = true }
windows-sys = { workspace = true }
[dev-dependencies]
proptest = { workspace = true }
TOML
cat > agent/src/main.rs <<'RS'
use anyhow::Result;
use clap::{ArgAction, Parser, Subcommand};
use std::path::PathBuf;
mod config; mod logging; mod collectors; mod transport; mod service;
use crate::config::load_config_with_precedence;
use crate::logging::init_tracing;
use crate::collectors::run_collect_loop;
#[derive(Parser, Debug)] #[command(name="agent", version, about="Rust Endpoint Agent (2025)")]
struct Cli{
  #[arg(short,long,env="REA_CONFIG")] config: Option<PathBuf>,
  #[arg(long,action=ArgAction::SetTrue)] enable_networking: bool,
  #[arg(long)] status_port: Option<u16>,
  #[command(subcommand)] command: Option<Commands>,
}
#[derive(Subcommand,Debug)] enum Commands{
  Run,
  Service{ #[command(subcommand)] cmd: ServiceCmd }
}
#[derive(Subcommand,Debug)] enum ServiceCmd{
  Install{ #[arg(long,default_value="Rust Endpoint Agent")] display_name:String,
           #[arg(long,default_value="Rust Endpoint Agent (transparent, no stealth)")] description:String,
           #[arg(long)] config:PathBuf },
  Uninstall,
}
#[tokio::main(flavor="multi_thread")]
async fn main()->Result<()>{
  let cli=Cli::parse();
  let mut cfg=load_config_with_precedence(cli.config.as_ref())?;
  if cli.enable_networking{ cfg.networking.enabled=true; }
  if let Some(p)=cli.status_port{ cfg.status.port=Some(p); }
  init_tracing(&cfg)?;
  match cli.command.unwrap_or(Commands::Run){
    Commands::Run=>{
      #[cfg(feature="status")]
      if let Some(port)=cfg.status.port{ crate::transport::status::spawn_status_server(port)?; }
      #[cfg(feature="networking")]
      let net_tx=crate::transport::modu::maybe_spawn_network_sender(&cfg).await?;
      run_collect_loop(cfg, #[cfg(feature="networking")] net_tx).await?;
    }
    Commands::Service{cmd}=>match cmd{
      ServiceCmd::Install{display_name,description,config}=>{
        #[cfg(target_os="windows")] { service::install::install_service(&display_name,&description,&config)?; println!("Service installed."); }
        #[cfg(not(target_os="windows"))] { eprintln!("Service install is Windows-only."); }
      }
      ServiceCmd::Uninstall=>{
        #[cfg(target_os="windows")] { service::uninstall::uninstall_service()?; println!("Service uninstalled."); }
        #[cfg(not(target_os="windows"))] { eprintln!("Service uninstall is Windows-only."); }
      }
    }
  }
  Ok(())
}
RS
cat > agent/src/lib.rs <<'RS'
pub mod config; pub mod logging; pub mod collectors; pub mod transport; pub mod service;
#[cfg(test)] mod tests{ use super::config::merge_config; use proptest::prelude::*; proptest!{
#[test] fn merge_config_prefers_b_over_a(s in ".*"){ let a=super::config::AgentConfig::default(); let mut b=a.clone(); b.common.instance_id=s.clone(); let m=merge_config(&a,&b); prop_assert_eq!(m.common.instance_id,s); } } }
RS
cat > agent/src/config.rs <<'RS'
use anyhow::{Context,Result}; use directories::ProjectDirs; use serde::{Deserialize,Serialize}; use std::{env,fs,path::{PathBuf}};
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct AgentConfig{ pub common:Common,pub collectors:Collectors,pub output:Output,pub networking:Networking,pub status:Status,}
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct Common{ pub instance_id:String,pub interval_secs:u64,pub max_event_bytes:usize,}
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct Collectors{ pub top_n_procs:usize,pub win_eventlog_channels:Vec<String>,pub win_eventlog_rps:u32,}
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct Output{ pub mode:String,pub file_path:Option<PathBuf>,pub rotate_bytes:usize,}
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct Networking{ pub enabled:bool,pub endpoint:String,pub batch_max_events:usize,pub batch_max_bytes:usize,pub flush_interval_ms:u64,pub queue_dir:PathBuf,pub queue_max_bytes:u64,pub ca_cert:Option<PathBuf>,pub client_cert:Option<PathBuf>,pub client_key:Option<PathBuf>,pub spki_pin_sha256:Option<String>,pub compression:String,pub retry_budget:usize,}
#[derive(Clone,Debug,Serialize,Deserialize)] pub struct Status{ pub port:Option<u16>,}
impl Default for AgentConfig{ fn default()->Self{ let pd=ProjectDirs::from("io","REA","agent").map(|p|p.data_dir().to_path_buf()).unwrap_or_else(||"./data".into());
 Self{ common:Common{instance_id:"rea-default".into(),interval_secs:5,max_event_bytes:128*1024},
 collectors:Collectors{top_n_procs:5,win_eventlog_channels:vec!["System".into(),"Application".into()],win_eventlog_rps:10},
 output:Output{mode:"stdout".into(),file_path:Some(pd.join("logs").join("agent.jsonl")),rotate_bytes:10*1024*1024},
 networking:Networking{enabled:false,endpoint:"https://127.0.0.1:8443/ingest".into(),batch_max_events:200,batch_max_bytes:512*1024,flush_interval_ms:2000,queue_dir:pd.join("queue"),queue_max_bytes:50*1024*1024,ca_cert:None,client_cert:None,client_key:None,spki_pin_sha256:None,compression:"zstd".into(),retry_budget:8},
 status:Status{port:None}, } } }
pub fn load_config_with_precedence(cli:Option<&PathBuf>)->Result<AgentConfig>{ let mut cfg=AgentConfig::default();
 if let Some(p)=cli{ if p.exists(){ let s=fs::read_to_string(p).with_context(||format!("reading config file {}",p.display()))?; let f:AgentConfig=toml::from_str(&s).context("parsing config TOML")?; cfg=merge_config(&cfg,&f);} }
 else if let Ok(env_path)=env::var("REA_CONFIG"){ let p:PathBuf=env_path.into(); if p.exists(){ let s=fs::read_to_string(&p).with_context(||format!("reading config file {}",p.display()))?; let f:AgentConfig=toml::from_str(&s).context("parsing config TOML")?; cfg=merge_config(&cfg,&f);} }
 if let Ok(v)=env::var("REA_INTERVAL_SECS"){ if let Ok(n)=v.parse::<u64>(){ cfg.common.interval_secs=n; } }
 if let Ok(v)=env::var("REA_ENABLE_NETWORKING"){ cfg.networking.enabled=v=="1"||v.eq_ignore_ascii_case("true"); }
 Ok(cfg) }
pub fn merge_config(a:&AgentConfig,b:&AgentConfig)->AgentConfig{ let mut out=a.clone(); out.common=b.common.clone(); out.collectors=b.collectors.clone(); out.output=b.output.clone(); out.networking=b.networking.clone(); out.status=b.status.clone(); out }
RS
cat > agent/src/logging.rs <<'RS'
use crate::config::AgentConfig; use anyhow::Result; use std::{fs,path::Path};
pub fn init_tracing(cfg:&AgentConfig)->Result<()>{
  let env_filter=std::env::var("RUST_LOG").unwrap_or_else(|_|"info,agent=info".into());
  if cfg.output.mode=="file"{
    if let Some(path)=&cfg.output.file_path{
      if let Some(dir)=path.parent(){ fs::create_dir_all(dir)?; }
      let file_appender=tracing_appender::rolling::never(path.parent().unwrap_or(Path::new(".")), path.file_name().unwrap());
      let (nb,guard)=tracing_appender::non_blocking(file_appender); Box::leak(Box::new(guard));
      tracing_subscriber::fmt().with_env_filter(env_filter).with_writer(nb).json().flatten_event(true).init();
    } else { tracing_subscriber::fmt().with_env_filter(env_filter).json().init(); }
  } else { tracing_subscriber::fmt().with_env_filter(env_filter).json().init(); }
  Ok(())
}
RS
cat > agent/src/collectors/mod.rs <<'RS'
use serde::Serialize; use time::{OffsetDateTime,format_description::well_known::Rfc3339}; use uuid::Uuid; use anyhow::Result; use tokio::sync::mpsc::Sender; use tracing::info;
pub mod cpu; pub mod mem; pub mod disk; pub mod net; pub mod proc; pub mod os; pub mod win_eventlog;
use crate::config::AgentConfig;
#[derive(Debug,Serialize,Clone)] pub struct TelemetryEnvelope<T:Serialize>{ pub ts:String,pub event_id:String,pub instance_id:String,pub kind:String,pub body:T,}
fn now_iso()->String{ OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_else(|_|"1970-01-01T00:00:00Z".into()) }
pub async fn run_collect_loop(cfg:AgentConfig, #[cfg(feature="networking")] net_tx:Option<Sender<Vec<u8>>>) -> Result<()>{
  let mut sys=sysinfo::System::new_all(); let interval=std::time::Duration::from_secs(cfg.common.interval_secs);
  #[cfg(all(target_os="windows",feature="win-events"))]
  let _evt_rx=win_eventlog::spawn_tailer(cfg.collectors.win_eventlog_channels.clone(), cfg.collectors.win_eventlog_rps)?;
  loop{
    sys.refresh_all();
    let instance=cfg.common.instance_id.clone();
    let cpu=cpu::collect(&mut sys); emit(&instance,"cpu",&cpu,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    let m=mem::collect(&mut sys); emit(&instance,"mem",&m,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    let d=disk::collect(&mut sys); emit(&instance,"disk",&d,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    let n=net::collect(&mut sys); emit(&instance,"net",&n,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    let p=proc::collect(&mut sys,cfg.collectors.top_n_procs); emit(&instance,"proc",&p,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    let o=os::collect(&sys); emit(&instance,"os",&o,cfg.common.max_event_bytes, #[cfg(feature="networking")] net_tx.clone());
    tokio::time::sleep(interval).await;
  }
}
fn emit<T:serde::Serialize>(instance_id:&str,kind:&str,body:&T,max_bytes:usize, #[cfg(feature="networking")] net_tx:Option<Sender<Vec<u8>>>){
  let env=TelemetryEnvelope{ ts:now_iso(), event_id:Uuid::new_v4().to_string(), instance_id:instance_id.to_string(), kind:kind.to_string(), body };
  if let Ok(mut line)=serde_json::to_vec(&env){ let _=line.push(b'\n'); if line.len()<=max_bytes{
    info!(event=%kind, size=line.len(), "telemetry");
    #[cfg(feature="networking")] if let Some(tx)=net_tx{ let _=tx.try_send(line); }
  } }
}
RS
cat > agent/src/collectors/cpu.rs <<'RS'
use serde::Serialize; use sysinfo::{CpuRefreshKind,RefreshKind,System};
#[derive(Debug,Serialize,Clone)] pub struct CpuStats{ pub global_cpu_percent:f32,pub load_avg_one:f64,pub load_avg_five:f64,pub load_avg_fifteen:f64,}
pub fn collect(sys:&mut System)->CpuStats{ sys.refresh_specifics(RefreshKind::new().with_cpu(CpuRefreshKind::everything())); let cpu=sys.global_cpu_info().cpu_usage(); let la=sys.load_average();
  CpuStats{ global_cpu_percent:cpu, load_avg_one:la.one, load_avg_five:la.five, load_avg_fifteen:la.fifteen } }
RS
cat > agent/src/collectors/mem.rs <<'RS'
use serde::Serialize; use sysinfo::{System,SystemExt};
#[derive(Debug,Serialize,Clone)] pub struct MemStats{ pub total:u64,pub used:u64,pub free:u64,}
pub fn collect(sys:&mut System)->MemStats{ sys.refresh_memory(); let total=sys.total_memory(); let used=sys.used_memory(); let free=total.saturating_sub(used); MemStats{total,used,free} }
RS
cat > agent/src/collectors/disk.rs <<'RS'
use serde::Serialize; use sysinfo::{Disks,System};
#[derive(Debug,Serialize,Clone)] pub struct DiskMount{ pub name:String,pub total:u64,pub available:u64,}
#[derive(Debug,Serialize,Clone)] pub struct DiskStats{ pub mounts:Vec<DiskMount>,}
pub fn collect(_sys:&mut System)->DiskStats{ let mut out=Vec::new(); let disks=Disks::new_with_refreshed_list(); for d in &disks{
  let name=d.name().to_string_lossy().to_string(); out.push(DiskMount{ name, total:d.total_space(), available:d.available_space() }); } DiskStats{mounts:out} }
RS
cat > agent/src/collectors/net.rs <<'RS'
use serde::Serialize; use sysinfo::{Networks,System};
#[derive(Debug,Serialize,Clone)] pub struct Iface{ pub name:String,pub total_received:u64,pub total_transmitted:u64,}
#[derive(Debug,Serialize,Clone)] pub struct NetStats{ pub ifaces:Vec<Iface>,}
pub fn collect(_sys:&mut System)->NetStats{ let nets=Networks::new_with_refreshed_list(); let mut out=Vec::new(); for (name,data) in nets.iter(){
  out.push(Iface{ name:name.to_string(), total_received:data.total_received(), total_transmitted:data.total_transmitted() }); } NetStats{ifaces:out} }
RS
cat > agent/src/collectors/proc.rs <<'RS'
use serde::Serialize; use sysinfo::{ProcessExt,System};
#[derive(Debug,Serialize,Clone)] pub struct ProcTop{ pub pid:i32,pub name:String,pub cpu_percent:f32,pub mem_bytes:u64,}
#[derive(Debug,Serialize,Clone)] pub struct ProcStats{ pub process_count:usize,pub top:Vec<ProcTop>,}
pub fn collect(sys:&mut System, top_n:usize)->ProcStats{ let mut v:Vec<ProcTop>=sys.processes().iter().map(|(pid,p)| ProcTop{ pid:pid.as_u32() as i32, name:p.name().to_string_lossy().to_string(), cpu_percent:p.cpu_usage(), mem_bytes:p.memory() }).collect();
  v.sort_by(|a,b| b.cpu_percent.partial_cmp(&a.cpu_percent).unwrap_or(std::cmp::Ordering::Equal)); v.truncate(top_n); ProcStats{ process_count:sys.processes().len(), top:v } }
RS
cat > agent/src/collectors/os.rs <<'RS'
use serde::Serialize; use sysinfo::System;
#[derive(Debug,Serialize,Clone)] pub struct OsStats{ pub name:Option<String>,pub version:Option<String>,pub kernel_version:Option<String>,pub host_name:Option<String>,pub uptime_secs:u64,pub boot_time_secs:u64,}
pub fn collect(sys:&System)->OsStats{ OsStats{ name:sys.name(), version:sys.os_version(), kernel_version:sys.kernel_version(), host_name:sys.host_name(), uptime_secs:sys.uptime().as_secs(), boot_time_secs:sys.boot_time().as_secs() } }
RS
cat > agent/src/collectors/win_eventlog.rs <<'RS'
#[cfg(all(target_os="windows",feature="win-events"))] use anyhow::Result;
#[cfg(all(target_os="windows",feature="win-events"))]
pub fn spawn_tailer(_channels:Vec<String>,_rps:u32)->Result<tokio::sync::mpsc::Receiver<String>>{
  let (tx,rx)=tokio::sync::mpsc::channel(100);
  tokio::spawn(async move{ loop{ let _=tx.send("win_eventlog_stub_heartbeat".to_string()).await; tokio::time::sleep(std::time::Duration::from_secs(10)).await; }});
  Ok(rx)
}
#[cfg(not(all(target_os="windows",feature="win-events")))]
pub fn spawn_tailer(_channels:Vec<String>,_rps:u32)->Result<tokio::sync::mpsc::Receiver<String>,anyhow::Error>{ anyhow::bail!("Windows-only with feature `win-events`"); }
RS
cat > agent/src/transport/mod.rs <<'RS'
pub mod mtls; pub mod client; pub mod queue;
#[cfg(feature="status")]
pub mod status{
  use anyhow::Result; use hyper::{Request,Response,Body,Method}; use hyper_util::rt::TokioIo; use tokio::net::TcpListener; use tracing::info;
  pub fn spawn_status_server(port:u16)->Result<()>{
    tokio::spawn(async move{ let addr=std::net::SocketAddr::from(([127,0,0,1],port)); let listener=TcpListener::bind(addr).await.expect("bind"); info!(%addr,"status server listening");
      loop{ let (stream,_)=listener.accept().await.expect("accept"); let io=TokioIo::new(stream);
        tokio::spawn(async move{ let conn=hyper::server::conn::http1::Builder::new().serve_connection(io, hyper::service::service_fn(handler)); if let Err(e)=conn.await{ tracing::warn!(error=?e,"status conn error"); } }); }});
    Ok(()) }
  async fn handler(req:Request<Body>)->Result<Response<Body>,hyper::Error>{
    match (req.method(),req.uri().path()){ (&Method::GET,"/healthz")=>Ok(Response::new(Body::from("ok"))), (&Method::GET,"/metrics")=>Ok(Response::new(Body::from("rea_up 1\n"))), _=>Ok(Response::builder().status(404).body(Body::empty()).unwrap()) } }
}
pub mod modu{
  use super::{client::NetClient,queue::DiskQueue}; use crate::config::AgentConfig; use anyhow::Result; use tokio::sync::mpsc::{self,Sender}; use tracing::{info,warn};
  #[cfg(feature="networking")]
  pub async fn maybe_spawn_network_sender(cfg:&AgentConfig)->Result<Option<Sender<Vec<u8>>>>{
    if !cfg.networking.enabled{ return Ok(None); }
    let (tx,mut rx)=mpsc::channel::<Vec<u8>>(1024);
    let mut queue=DiskQueue::open(&cfg.networking.queue_dir, cfg.networking.queue_max_bytes).await?; let client=NetClient::new(cfg).await?;
    let endpoint=cfg.networking.endpoint.clone(); let flush_every=std::time::Duration::from_millis(cfg.networking.flush_interval_ms); let compression=cfg.networking.compression.clone(); let retry_budget=cfg.networking.retry_budget;
    tokio::spawn(async move{ let mut budget=retry_budget; loop{
      tokio::select!{
        Some(line)=rx.recv()=>{ if let Err(e)=queue.enqueue(line).await{ warn!(error=?e,"enqueue failed"); } }
        _=tokio::time::sleep(flush_every)=>{ let mut batch=Vec::new(); let mut bytes:usize=0;
          while let Ok(Some(item))=queue.peek_oldest().await{ if bytes+item.len()>512*1024{ break; } bytes+=item.len(); batch.push(item); let _=queue.pop_oldest().await; }
          if batch.is_empty(){ continue; }
          match client.post_ndjson(&endpoint,batch,&compression).await{
            Ok(_)=>{ budget=retry_budget; info!("batch delivered"); }
            Err(e)=>{ warn!(error=?e,"post failed"); budget=budget.saturating_sub(1); if budget==0{ warn!("retry budget exhausted; dropping until next cycle"); } }
          }
        }
      } }});
    Ok(Some(tx))
  }
}
RS
cat > agent/src/transport/mtls.rs <<'RS'
use anyhow::{Context,Result}; use reqwest::{Client,Certificate,Identity}; use std::{fs,path::Path};
pub struct TlsMaterials{ pub ca:Option<Certificate>, pub identity:Option<Identity>, }
pub fn load_tls(ca:Option<&Path>, cert:Option<&Path>, key:Option<&Path>)->Result<TlsMaterials>{
  let ca=if let Some(p)=ca{ let pem=fs::read(p).with_context(||format!("reading CA {}",p.display()))?; Some(Certificate::from_pem(&pem).context("parsing CA PEM")?) } else { None };
  let identity=match (cert,key){ (Some(cp),Some(kp))=>{ let mut pem=Vec::new(); pem.extend(fs::read(cp).with_context(||format!("reading client cert {}",cp.display()))?); pem.extend(b"\n"); pem.extend(fs::read(kp).with_context(||format!("reading client key {}",kp.display()))?); Some(Identity::from_pem(&pem).context("parsing client identity PEM (PKCS8)")?) }, _=>None };
  Ok(TlsMaterials{ca,identity})
}
pub fn build_client(tls:&TlsMaterials)->Result<Client>{
  let mut b=reqwest::Client::builder().use_rustls_tls().http2_prior_knowledge(false).http2_adaptive_window(true).tcp_nodelay(true).pool_max_idle_per_host(2);
  if let Some(ca)=&tls.ca{ b=b.add_root_certificate(ca.clone()); }
  if let Some(id)=&tls.identity{ b=b.identity(id.clone()); }
  Ok(b.build().context("building reqwest client")?)
}
RS
cat > agent/src/transport/client.rs <<'RS'
use anyhow::{Context,Result}; use reqwest::Client; use crate::config::AgentConfig; use super::mtls::{load_tls,build_client};
pub struct NetClient{ client:Client }
impl NetClient{
  pub async fn new(cfg:&AgentConfig)->Result<Self>{ let tls=load_tls(cfg.networking.ca_cert.as_deref(), cfg.networking.client_cert.as_deref(), cfg.networking.client_key.as_deref())?; let client=build_client(&tls)?; Ok(Self{client}) }
  pub async fn post_ndjson(&self, endpoint:&str, lines:Vec<Vec<u8>>, compression:&str)->Result<()>{
    let mut body=Vec::new(); for mut l in lines{ body.append(&mut l); }
    let mut req=self.client.post(endpoint);
    if compression.eq_ignore_ascii_case("zstd"){ let compressed=zstd::stream::encode_all(&body[..],3).context("zstd compress")?; req=req.header("Content-Type","application/x-ndjson").header("Content-Encoding","zstd").body(compressed);
    } else { req=req.header("Content-Type","application/x-ndjson").body(body); }
    let resp=req.send().await.context("send request")?; if !resp.status().is_success(){ anyhow::bail!("server status {}",resp.status()); } Ok(())
  }
}
RS
cat > agent/src/transport/queue.rs <<'RS'
use anyhow::{Result}; use tokio::{fs,io::AsyncWriteExt}; use std::{path::{Path,PathBuf}}; use rand::{distributions::Alphanumeric,Rng};
pub struct DiskQueue{ dir:PathBuf, cap_bytes:u64 }
impl DiskQueue{
  pub async fn open(dir:&Path, cap:u64)->Result<Self>{ fs::create_dir_all(dir).await?; Ok(Self{dir:dir.to_path_buf(),cap_bytes:cap}) }
  pub async fn enqueue(&mut self, data:Vec<u8>)->Result<()> { self.enforce_cap().await?; let name=format!("{}-{}.ndjson", now_ms(), rand_str(6)); let p=self.dir.join(name); let mut f=fs::File::create(&p).await?; f.write_all(&data).await?; Ok(()) }
  pub async fn peek_oldest(&self)->Result<Option<Vec<u8>>>{ let mut rd=fs::read_dir(&self.dir).await?; let mut files:Vec<PathBuf>=Vec::new(); while let Some(e)=rd.next_entry().await?{ if e.metadata().await?.is_file(){ files.push(e.path()); } } files.sort(); if let Some(f)=files.first(){ return Ok(Some(fs::read(f).await?)); } Ok(None) }
  pub async fn pop_oldest(&self)->Result<()> { let mut rd=fs::read_dir(&self.dir).await?; let mut files:Vec<PathBuf>=Vec::new(); while let Some(e)=rd.next_entry().await?{ if e.metadata().await?.is_file(){ files.push(e.path()); } } files.sort(); if let Some(f)=files.first(){ fs::remove_file(f).await?; } Ok(()) }
  async fn enforce_cap(&self)->Result<()>{
    let mut rd=fs::read_dir(&self.dir).await?; let mut files:Vec<(PathBuf,u64)>=Vec::new(); let mut total=0u64;
    while let Some(e)=rd.next_entry().await?{ let p=e.path(); let md=e.metadata().await?; if md.is_file(){ let sz=md.len(); total+=sz; files.push((p,sz)); } }
    files.sort_by(|a,b| a.0.cmp(&b.0));
    while total>self.cap_bytes{ if let Some((old,sz))=files.first().cloned(){ let _=fs::remove_file(&old).await; total=total.saturating_sub(sz); files.remove(0);} else {break;} }
    Ok(())
  }
}
fn rand_str(n:usize)->String{ rand::thread_rng().sample_iter(&Alphanumeric).take(n).map(char::from).collect() }
fn now_ms()->i128{ use time::OffsetDateTime; OffsetDateTime::now_utc().unix_timestamp_nanos() as i128 / 1_000_000 }
RS
cat > agent/src/service/mod.rs <<'RS'
#[cfg(target_os="windows")] pub mod install;
#[cfg(target_os="windows")] pub mod uninstall;
// SCM runs: agent.exe run --config <path>
RS
cat > agent/src/service/install.rs <<'RS'
#[cfg(target_os="windows")] use anyhow::{Context,Result};
#[cfg(target_os="windows")] use std::path::Path;
#[cfg(target_os="windows")] use windows_service::{ service::{ServiceAccess,ServiceErrorControl,ServiceInfo,ServiceStartType,ServiceType}, service_manager::{ServiceManager,ServiceManagerAccess}, };
#[cfg(target_os="windows")]
pub fn install_service(display_name:&str, description:&str, config_path:&Path)->Result<()>{
  let mgr=ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT|ServiceManagerAccess::CREATE_SERVICE)?;
  let exe=std::env::current_exe().context("current_exe")?;
  let info=ServiceInfo{ name:"RustEndpointAgent".into(), display_name:display_name.into(), service_type:ServiceType::OWN_PROCESS, start_type:ServiceStartType::Automatic, error_control:ServiceErrorControl::Normal, executable_path:exe, launch_arguments:vec!["run".into(),"--config".into(),config_path.display().to_string()], dependencies:vec![], account_name:None, account_password:None };
  let svc=mgr.create_service(&info, ServiceAccess::all()).context("create service")?;
  let _=svc.set_description(description); let _=svc.start(&[]);
  Ok(())
}
RS
cat > agent/src/service/uninstall.rs <<'RS'
#[cfg(target_os="windows")] use anyhow::{Context,Result};
#[cfg(target_os="windows")] use windows_service::{ service::{ServiceAccess,ServiceState}, service_manager::{ServiceManager,ServiceManagerAccess}, };
#[cfg(target_os="windows")]
pub fn uninstall_service()->Result<()>{
  let mgr=ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?; let svc=mgr.open_service("RustEndpointAgent", ServiceAccess::all()).context("open service")?;
  if let Ok(st)=svc.query_status(){ if st.current_state!=ServiceState::Stopped{ let _=svc.stop(); } }
  svc.delete().context("delete service")?; Ok(())
}
RS
cat > server/Cargo.toml <<'TOML'
[package]
name = "server"
version = "0.1.0"
edition = "2021"
license = "Apache-2.0"
description = "Local HTTPS test receiver for the Rust Endpoint Agent."
[dependencies]
anyhow = { workspace = true }
tokio = { workspace = true }
hyper = { workspace = true }
hyper-util = { workspace = true }
http = { workspace = true }
rustls = { workspace = true }
rustls-pemfile = { workspace = true }
tokio-rustls = { workspace = true }
time = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
zstd = { workspace = true }
bytes = { workspace = true }
TOML
cat > server/src/main.rs <<'RS'
use anyhow::{Context,Result}; use hyper::{Request,Response,Body,Method}; use hyper_util::rt::TokioIo; use std::{fs::File,io::BufReader,path::PathBuf,io::Write}; use tokio::net::TcpListener; use tokio_rustls::TlsAcceptor; use rustls::{ServerConfig, pki_types::{CertificateDer,PrivateKeyDer}}; use rustls_pemfile::{certs,pkcs8_private_keys}; use time::{OffsetDateTime,format_description::well_known::Rfc3339}; use tracing::info;
#[tokio::main] async fn main()->Result<()>{
  tracing_subscriber::fmt().with_env_filter("info,server=info").json().init();
  let mut args=std::env::args().skip(1); let cert:PathBuf=args.next().unwrap_or_else(||"configs/certs/server.crt".into()); let key:PathBuf=args.next().unwrap_or_else(||"configs/certs/server.key".into()); let addr="127.0.0.1:8443";
  let cfg=tls_config(&cert,&key).context("tls config")?; let acceptor=TlsAcceptor::from(std::sync::Arc::new(cfg)); let listener=TcpListener::bind(addr).await?; info!(%addr,"HTTPS receiver listening");
  loop{ let (tcp, _)=listener.accept().await?; let acceptor=acceptor.clone(); tokio::spawn(async move{
    let tls=match acceptor.accept(tcp).await{ Ok(s)=>s, Err(e)=>{ tracing::warn!(error=?e,"TLS accept"); return; } }; let io=TokioIo::new(tls);
    if let Err(e)=hyper::server::conn::http1::Builder::new().serve_connection(io, hyper::service::service_fn(handler)).await{ tracing::warn!(error=?e,"connection failed"); }
  }); }
}
async fn handler(req:Request<Body>)->Result<Response<Body>,hyper::Error>{
  match (req.method(),req.uri().path()){
    (&Method::POST,"/ingest")=>{
      let mut body=hyper::body::to_bytes(req.into_body()).await?;
      if body.starts_with(&[40,181,47,253]){ if let Ok(decompressed)=zstd::stream::decode_all(&body[..]){ body=bytes::Bytes::from(decompressed); } }
      let now=OffsetDateTime::now_utc().format(&Rfc3339).unwrap(); print!("{} ",now); std::io::stdout().write_all(&body).ok(); Ok(Response::new(Body::from("ok")))
    }
    _=>Ok(Response::builder().status(404).body(Body::empty()).unwrap())
  }
}
fn tls_config(cert_path:&PathBuf, key_path:&PathBuf)->Result<ServerConfig>{
  let cert_file=&mut BufReader::new(File::open(cert_path)?); let key_file=&mut BufReader::new(File::open(key_path)?);
  let certs:Vec<CertificateDer<'static>>=certs(cert_file)?.into_iter().collect(); let mut keys:Vec<PrivateKeyDer>=pkcs8_private_keys(key_file)?.into_iter().map(Into::into).collect(); let key=keys.remove(0);
  let cfg=rustls::ServerConfig::builder().with_no_client_auth().with_single_cert(certs,key)?; Ok(cfg)
}
RS
cat > xtask/Cargo.toml <<'TOML'
[package]
name = "xtask"
version = "0.1.0"
edition = "2021"
license = "Apache-2.0"
description = "Developer tasks for the Rust Endpoint Agent."
[dependencies]
anyhow = { workspace = true }
clap = { workspace = true }
rcgen = "0.13"
time = { workspace = true }
TOML
cat > xtask/src/main.rs <<'RS'
use anyhow::Result; use clap::{Parser,Subcommand}; use std::{fs,path::PathBuf};
#[derive(Parser,Debug)] #[command(name="xtask")] struct Cli{ #[command(subcommand)] cmd:Commands }
#[derive(Subcommand,Debug)] enum Commands{ Certs{ #[arg(long,default_value="127.0.0.1")] dns:String }, Lint, }
fn main()->Result<()>{
  let cli=Cli::parse(); match cli.cmd{
    Commands::Certs{dns}=>{ let dir=PathBuf::from("configs/certs"); fs::create_dir_all(&dir)?; let mut p=rcgen::CertificateParams::new(vec![dns]); p.alg=&rcgen::PKCS_ECDSA_P256_SHA256; let cert=rcgen::Certificate::from_params(p)?; let crt=cert.serialize_pem()?; let key=cert.serialize_private_key_pem(); fs::write(dir.join("server.crt"),&crt)?; fs::write(dir.join("server.key"),&key)?; println!("Wrote configs/certs/server.crt and server.key"); }
    Commands::Lint=>{ run("cargo",&["fmt","--all"])?; run("cargo",&["clippy","--all-targets","--","-Dwarnings"])?; }
  } Ok(()) }
fn run(cmd:&str,args:&[&str])->Result<()> { println!("+ {} {}",cmd,args.join(" ")); let st=std::process::Command::new(cmd).args(args).status()?; if !st.success(){ anyhow::bail!("command failed") } Ok(()) }
RS
cat > configs/agent.example.toml <<'TOML'
[common] instance_id="rea-lab-001" interval_secs=5 max_event_bytes=131072
[collectors] top_n_procs=5 win_eventlog_channels=["System","Application"] win_eventlog_rps=10
[output] mode="stdout" file_path="C:\\ProgramData\\REA\\logs\\agent.jsonl" rotate_bytes=10485760
[networking]
enabled=false
endpoint="https://127.0.0.1:8443/ingest"
batch_max_events=200
batch_max_bytes=524288
flush_interval_ms=2000
queue_dir="C:\\ProgramData\\REA\\queue"
queue_max_bytes=52428800
ca_cert="C:\\ProgramData\\REA\\tls\\ca.crt"
client_cert="C:\\ProgramData\\REA\\tls\\client.crt"
client_key="C:\\ProgramData\\REA\\tls\\client.key"
spki_pin_sha256=""
compression="zstd"
retry_budget=8
[status] port=0
TOML
cat > configs/server.example.toml <<'TOML'
cert = "configs/certs/server.crt"
key  = "configs/certs/server.key"
listen = "127.0.0.1:8443"
TOML
cat > SECURITY.md <<'MD'
# Security Policy
Report potential vulnerabilities to security@your-org.example (coordinated disclosure). No stealth, no self-update, no hidden persistence.
MD
cat > CODE_OF_CONDUCT.md <<'MD'
# Code of Conduct
Be respectful and inclusive. Report incidents to coc@your-org.example.
MD
cat > CONTRIBUTING.md <<'MD'
# Contributing
Use Rust stable. Run `cargo fmt`, `cargo clippy -D warnings`, `cargo test`.
MD
cat > LICENSE <<'TXT'
Apache-2.0 (placeholder). Replace with full text for distribution.
TXT
cat > .github/workflows/ci.yml <<'YML'
name: ci
on: [push, pull_request]
permissions: { contents: read, id-token: write }
jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo fmt --all -- --check
      - run: cargo clippy --all-targets -- -D warnings
      - run: cargo test --all --all-features --no-fail-fast
      - name: audit
        uses: actions-rs/audit-check@v1
  build-windows-gnu:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: sudo apt-get update && sudo apt-get install -y mingw-w64 gcc-mingw-w64-x86-64 zstd
      - run: rustup target add x86_64-pc-windows-gnu
      - run: cargo build --release -p agent --target x86_64-pc-windows-gnu
      - run: (cd target/x86_64-pc-windows-gnu/release && sha256sum agent.exe > agent.exe.sha256)
      - uses: actions/upload-artifact@v4
        with:
          name: agent-windows-gnu
          path: |
            target/x86_64-pc-windows-gnu/release/agent.exe
            target/x86_64-pc-windows-gnu/release/agent.exe.sha256
YML
cat > README.md <<'MD'
Rust Endpoint Agent (2025) — Windows-first, modular telemetry agent with mTLS and enterprise-grade hardening.
MD
git init
git add .
git commit -m "feat: initial Rust Endpoint Agent workspace (agent/server/xtask)"
