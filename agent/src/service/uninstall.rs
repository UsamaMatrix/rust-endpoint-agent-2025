#[cfg(target_os = "windows")]
use anyhow::{Context, Result};
#[cfg(target_os = "windows")]
use windows_service::{
    service::{ServiceAccess, ServiceState},
    service_manager::{ServiceManager, ServiceManagerAccess},
};
#[cfg(target_os = "windows")]
pub fn uninstall_service() -> Result<()> {
    let mgr = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)?;
    let svc = mgr
        .open_service("RustEndpointAgent", ServiceAccess::all())
        .context("open service")?;
    if let Ok(st) = svc.query_status() {
        if st.current_state != ServiceState::Stopped {
            let _ = svc.stop();
        }
    }
    svc.delete().context("delete service")?;
    Ok(())
}
