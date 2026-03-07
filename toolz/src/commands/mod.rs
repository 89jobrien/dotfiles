pub mod ai;
pub mod db;
pub mod log;
pub mod sys;

use crate::cli::Commands;
use anyhow::Result;
use tracing::instrument;

#[instrument(skip_all)]
pub async fn dispatch(cmd: Commands) -> Result<()> {
    match cmd {
        Commands::Sys(args) => sys::run(args).await,
        Commands::Log { action } => log::run(action).await,
        Commands::Ai { action } => ai::run(action).await,
        Commands::Db { action } => db::run(action).await,
    }
}
