use anyhow::Result;
use clap::{ArgAction, Parser, Subcommand};
use std::path::PathBuf;
mod collectors;
mod config;
mod logging;
mod service;
mod transport;
use crate::collectors::run_collect_loop;
use crate::config::load_config_with_precedence;
use crate::logging::init_tracing;
#[derive(Parser, Debug)]
#[command(name = "agent", version, about = "Rust Endpoint Agent (2025)")]
struct Cli {
    #[arg(short, long, env = "REA_CONFIG")]
    config: Option<PathBuf>,
    #[arg(long,action=ArgAction::SetTrue)]
    enable_networking: bool,
    #[arg(long)]
    status_port: Option<u16>,
    #[command(subcommand)]
    command: Option<Commands>,
}
#[derive(Subcommand, Debug)]
enum Commands {
    Run,
    Service {
        #[command(subcommand)]
        cmd: ServiceCmd,
    },
}
#[derive(Subcommand, Debug)]
enum ServiceCmd {
    Install {
        #[arg(long, default_value = "Rust Endpoint Agent")]
        display_name: String,
        #[arg(long, default_value = "Rust Endpoint Agent (transparent, no stealth)")]
        description: String,
        #[arg(long)]
        config: PathBuf,
    },
    Uninstall,
}
#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut cfg = load_config_with_precedence(cli.config.as_ref())?;
    if cli.enable_networking {
        cfg.networking.enabled = true;
    }
    if let Some(p) = cli.status_port {
        cfg.status.port = Some(p);
    }
    init_tracing(&cfg)?;
    match cli.command.unwrap_or(Commands::Run) {
        Commands::Run => {
            #[cfg(feature = "status")]
            if let Some(port) = cfg.status.port {
                crate::transport::status::spawn_status_server(port)?;
            }
            #[cfg(feature = "networking")]
            let net_tx = crate::transport::modu::maybe_spawn_network_sender(&cfg).await?;
            run_collect_loop(
                cfg,
                #[cfg(feature = "networking")]
                net_tx,
            )
            .await?;
        }
        Commands::Service { cmd } => match cmd {
            ServiceCmd::Install {
                display_name,
                description,
                config,
            } => {
                #[cfg(target_os = "windows")]
                {
                    service::install::install_service(&display_name, &description, &config)?;
                    println!("Service installed.");
                }
                #[cfg(not(target_os = "windows"))]
                {
                    eprintln!("Service install is Windows-only.");
                }
            }
            ServiceCmd::Uninstall => {
                #[cfg(target_os = "windows")]
                {
                    service::uninstall::uninstall_service()?;
                    println!("Service uninstalled.");
                }
                #[cfg(not(target_os = "windows"))]
                {
                    eprintln!("Service uninstall is Windows-only.");
                }
            }
        },
    }
    Ok(())
}
