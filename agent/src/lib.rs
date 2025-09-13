pub mod collectors;
pub mod config;
pub mod logging;
pub mod service;
pub mod transport;
#[cfg(test)]
mod tests {
    use super::config::merge_config;
    use proptest::prelude::*;
    proptest! {
    #[test] fn merge_config_prefers_b_over_a(s in ".*"){ let a=super::config::AgentConfig::default(); let mut b=a.clone(); b.common.instance_id=s.clone(); let m=merge_config(&a,&b); prop_assert_eq!(m.common.instance_id,s); } }
}
// touch
