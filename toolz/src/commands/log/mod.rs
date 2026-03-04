pub mod analyze;
pub mod errors;

use crate::cli::LogAction;
use anyhow::Result;

pub async fn run(action: LogAction) -> Result<()> {
    match action {
        LogAction::Analyze { file } => analyze::run(&file),
        LogAction::Errors { file, pattern } => errors::run(&file, pattern.as_deref()),
    }
}
