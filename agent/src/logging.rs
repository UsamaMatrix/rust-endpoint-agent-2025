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
