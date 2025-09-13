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
