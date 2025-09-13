#[cfg(all(target_os="windows",feature="win-events"))] use anyhow::Result;
#[cfg(all(target_os="windows",feature="win-events"))]
pub fn spawn_tailer(_channels:Vec<String>,_rps:u32)->Result<tokio::sync::mpsc::Receiver<String>>{
  let (tx,rx)=tokio::sync::mpsc::channel(100);
  tokio::spawn(async move{ loop{ let _=tx.send("win_eventlog_stub_heartbeat".to_string()).await; tokio::time::sleep(std::time::Duration::from_secs(10)).await; }});
  Ok(rx)
}
#[cfg(not(all(target_os="windows",feature="win-events")))]
pub fn spawn_tailer(_channels:Vec<String>,_rps:u32)->Result<tokio::sync::mpsc::Receiver<String>,anyhow::Error>{ anyhow::bail!("Windows-only with feature `win-events`"); }
