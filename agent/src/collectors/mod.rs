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
