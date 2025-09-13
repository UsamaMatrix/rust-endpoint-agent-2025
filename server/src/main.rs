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
