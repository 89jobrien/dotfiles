use clap::Parser;

mod cli;
mod commands;
mod config;
mod observability;
mod output;
mod tui;

use cli::Cli;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        None => {
            // TUI mode: no stdout/stderr tracing — would corrupt the terminal.
            // Logs go to file + ring buffer (displayed on the Traces screen).
            let (log_buffer, _tracing_guard) = observability::init_tui()?;
            tui::run_tui(log_buffer)?;
        }
        Some(cmd) => {
            // CLI mode: file log + compact stderr output.
            let _tracing_guard = observability::init_cli()?;
            commands::dispatch(cmd).await?;
        }
    }

    Ok(())
}
