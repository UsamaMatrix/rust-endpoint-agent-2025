use serde::Serialize; use sysinfo::System;
#[derive(Debug,Serialize,Clone)] pub struct OsStats{ pub name:Option<String>,pub version:Option<String>,pub kernel_version:Option<String>,pub host_name:Option<String>,pub uptime_secs:u64,pub boot_time_secs:u64,}
pub fn collect(sys:&System)->OsStats{ OsStats{ name:sys.name(), version:sys.os_version(), kernel_version:sys.kernel_version(), host_name:sys.host_name(), uptime_secs:sys.uptime().as_secs(), boot_time_secs:sys.boot_time().as_secs() } }
