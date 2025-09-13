use serde::Serialize; use sysinfo::{Networks,System};
#[derive(Debug,Serialize,Clone)] pub struct Iface{ pub name:String,pub total_received:u64,pub total_transmitted:u64,}
#[derive(Debug,Serialize,Clone)] pub struct NetStats{ pub ifaces:Vec<Iface>,}
pub fn collect(_sys:&mut System)->NetStats{ let nets=Networks::new_with_refreshed_list(); let mut out=Vec::new(); for (name,data) in nets.iter(){
  out.push(Iface{ name:name.to_string(), total_received:data.total_received(), total_transmitted:data.total_transmitted() }); } NetStats{ifaces:out} }
