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
