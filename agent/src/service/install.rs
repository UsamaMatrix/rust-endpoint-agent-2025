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
