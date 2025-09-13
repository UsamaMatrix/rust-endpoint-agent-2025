use serde::Serialize; use sysinfo::{System,SystemExt};
#[derive(Debug,Serialize,Clone)] pub struct MemStats{ pub total:u64,pub used:u64,pub free:u64,}
pub fn collect(sys:&mut System)->MemStats{ sys.refresh_memory(); let total=sys.total_memory(); let used=sys.used_memory(); let free=total.saturating_sub(used); MemStats{total,used,free} }
