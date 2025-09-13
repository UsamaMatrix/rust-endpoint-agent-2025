use serde::Serialize; use sysinfo::{ProcessExt,System};
#[derive(Debug,Serialize,Clone)] pub struct ProcTop{ pub pid:i32,pub name:String,pub cpu_percent:f32,pub mem_bytes:u64,}
#[derive(Debug,Serialize,Clone)] pub struct ProcStats{ pub process_count:usize,pub top:Vec<ProcTop>,}
pub fn collect(sys:&mut System, top_n:usize)->ProcStats{ let mut v:Vec<ProcTop>=sys.processes().iter().map(|(pid,p)| ProcTop{ pid:pid.as_u32() as i32, name:p.name().to_string_lossy().to_string(), cpu_percent:p.cpu_usage(), mem_bytes:p.memory() }).collect();
  v.sort_by(|a,b| b.cpu_percent.partial_cmp(&a.cpu_percent).unwrap_or(std::cmp::Ordering::Equal)); v.truncate(top_n); ProcStats{ process_count:sys.processes().len(), top:v } }
