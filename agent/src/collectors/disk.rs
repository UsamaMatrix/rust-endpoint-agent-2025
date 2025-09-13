use serde::Serialize;
use sysinfo::{Disks, System};
#[derive(Debug, Serialize, Clone)]
pub struct DiskMount {
    pub name: String,
    pub total: u64,
    pub available: u64,
}
#[derive(Debug, Serialize, Clone)]
pub struct DiskStats {
    pub mounts: Vec<DiskMount>,
}
pub fn collect(_sys: &mut System) -> DiskStats {
    let mut out = Vec::new();
    let disks = Disks::new_with_refreshed_list();
    for d in &disks {
        let name = d.name().to_string_lossy().to_string();
        out.push(DiskMount {
            name,
            total: d.total_space(),
            available: d.available_space(),
        });
    }
    DiskStats { mounts: out }
}
