pub mod config;
pub mod runner;

use crate::cli::DbAction;
use anyhow::Result;

pub async fn run(action: DbAction) -> Result<()> {
    match action {
        DbAction::List => config::list(),
        DbAction::Connect { name } => runner::connect(&name),
        DbAction::Query { name, sql } => runner::query(&name, &sql),
        DbAction::Add { name, driver, url } => config::add(&name, &driver, &url),
        DbAction::Backup { name, output } => runner::backup(&name, output.as_deref()),
    }
}
