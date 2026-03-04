use clap::Parser;
use tracing_subscriber::EnvFilter;

mod cli;
mod commands;
mod config;
mod output;
mod tui;

use cli::Cli;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(false)
        .init();

    let cli = Cli::parse();

    match cli.command {
        None => tui::run_tui()?,
        Some(cmd) => commands::dispatch(cmd).await?,
    }

    Ok(())
}
