use serde::Serialize; use sysinfo::{CpuRefreshKind,RefreshKind,System};
#[derive(Debug,Serialize,Clone)] pub struct CpuStats{ pub global_cpu_percent:f32,pub load_avg_one:f64,pub load_avg_five:f64,pub load_avg_fifteen:f64,}
pub fn collect(sys:&mut System)->CpuStats{ sys.refresh_specifics(RefreshKind::new().with_cpu(CpuRefreshKind::everything())); let cpu=sys.global_cpu_info().cpu_usage(); let la=sys.load_average();
  CpuStats{ global_cpu_percent:cpu, load_avg_one:la.one, load_avg_five:la.five, load_avg_fifteen:la.fifteen } }
