use anyhow::{Context, Result};
use reqwest::{Certificate, Client, Identity};
use std::{fs, path::Path};
pub struct TlsMaterials {
    pub ca: Option<Certificate>,
    pub identity: Option<Identity>,
}
pub fn load_tls(
    ca: Option<&Path>,
    cert: Option<&Path>,
    key: Option<&Path>,
) -> Result<TlsMaterials> {
    let ca = if let Some(p) = ca {
        let pem = fs::read(p).with_context(|| format!("reading CA {}", p.display()))?;
        Some(Certificate::from_pem(&pem).context("parsing CA PEM")?)
    } else {
        None
    };
    let identity = match (cert, key) {
        (Some(cp), Some(kp)) => {
            let mut pem = Vec::new();
            pem.extend(
                fs::read(cp).with_context(|| format!("reading client cert {}", cp.display()))?,
            );
            pem.extend(b"\n");
            pem.extend(
                fs::read(kp).with_context(|| format!("reading client key {}", kp.display()))?,
            );
            Some(Identity::from_pem(&pem).context("parsing client identity PEM (PKCS8)")?)
        }
        _ => None,
    };
    Ok(TlsMaterials { ca, identity })
}
pub fn build_client(tls: &TlsMaterials) -> Result<Client> {
    let mut b = reqwest::Client::builder()
        .use_rustls_tls()
        .http2_prior_knowledge(false)
        .http2_adaptive_window(true)
        .tcp_nodelay(true)
        .pool_max_idle_per_host(2);
    if let Some(ca) = &tls.ca {
        b = b.add_root_certificate(ca.clone());
    }
    if let Some(id) = &tls.identity {
        b = b.identity(id.clone());
    }
    Ok(b.build().context("building reqwest client")?)
}
