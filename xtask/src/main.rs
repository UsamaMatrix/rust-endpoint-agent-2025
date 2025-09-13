use anyhow::Result;
use clap::{Parser, Subcommand};
use std::{fs, path::PathBuf};

#[derive(Parser, Debug)]
#[command(name = "xtask")]
struct Cli {
    #[command(subcommand)]
    cmd: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Generate self-signed TLS cert/key for local testing
    Certs {
        #[arg(long, default_value = "127.0.0.1")]
        dns: String,
    },
    /// Run fmt+clippy
    Lint,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Commands::Certs { dns } => {
            let dir = PathBuf::from("configs/certs");
            fs::create_dir_all(&dir)?;
            // Simple & stable API
            let cert = rcgen::generate_simple_self_signed(vec![dns])?;
            let crt = cert.serialize_pem()?;
            let key = cert.serialize_private_key_pem();
            fs::write(dir.join("server.crt"), crt)?;
            fs::write(dir.join("server.key"), key)?;
            println!("Wrote configs/certs/server.crt and server.key");
        }
        Commands::Lint => {
            run("cargo", &["fmt", "--all"])?;
            run("cargo", &["clippy", "--all-targets", "--", "-Dwarnings"])?;
        }
    }
    Ok(())
}

fn run(cmd: &str, args: &[&str]) -> Result<()> {
    println!("+ {} {}", cmd, args.join(" "));
    let st = std::process::Command::new(cmd).args(args).status()?;
    if !st.success() {
        anyhow::bail!("command failed")
    }
    Ok(())
}
