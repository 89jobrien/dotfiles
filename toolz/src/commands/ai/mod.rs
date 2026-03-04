pub mod chat;
pub mod provider;
pub mod rag;

use crate::cli::{AiAction, RagAction};
use anyhow::Result;

pub async fn run(action: AiAction) -> Result<()> {
    match action {
        AiAction::Chat { provider, model } => chat::run(provider, model).await,
        AiAction::Rag { action } => match action {
            RagAction::Add { path } => rag::add(&path).await,
            RagAction::Query { query, top_k } => rag::query(&query, top_k).await,
            RagAction::Status => rag::status().await,
        },
    }
}
