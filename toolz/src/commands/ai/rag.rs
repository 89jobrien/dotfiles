use super::provider::{build_provider, Message};
use crate::config;
use anyhow::{Context, Result};
use fastembed::{EmbeddingModel, InitOptions, TextEmbedding};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Serialize, Deserialize, Default)]
pub struct RagStore {
    pub chunks: Vec<Chunk>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Chunk {
    pub text: String,
    pub embedding: Vec<f32>,
    pub source: String,
}

const CHUNK_SIZE: usize = 512;
const CHUNK_OVERLAP: usize = 64;

// ── Public entry points ──────────────────────────────────────────────────────

pub async fn add(path: &str) -> Result<()> {
    let model = load_model()?;
    let mut store = load_store()?;

    let input_path = Path::new(path);
    let files = collect_files(input_path)?;

    println!("adding {} file(s) to RAG store...", files.len());

    for file in &files {
        let text = std::fs::read_to_string(file)
            .with_context(|| format!("reading {}", file.display()))?;

        let chunks = chunk_text(&text, CHUNK_SIZE, CHUNK_OVERLAP);
        let source = file.to_string_lossy().to_string();

        // Remove old chunks from same source
        store.chunks.retain(|c| c.source != source);

        let embeddings = model
            .embed(chunks.clone(), None)
            .with_context(|| format!("embedding {}", file.display()))?;

        for (text, embedding) in chunks.into_iter().zip(embeddings.into_iter()) {
            store.chunks.push(Chunk { text, embedding, source: source.clone() });
        }

        println!("  \x1b[32m✓\x1b[0m {}", file.display());
    }

    save_store(&store)?;
    println!("\nstore: {} chunks total", store.chunks.len());
    Ok(())
}

pub async fn query(query_text: &str, top_k: usize) -> Result<()> {
    let cfg = config::load()?;
    let model = load_model()?;
    let store = load_store()?;

    if store.chunks.is_empty() {
        println!("RAG store is empty. Run `toolz ai rag add <path>` first.");
        return Ok(());
    }

    let query_embedding = model
        .embed(vec![query_text.to_string()], None)
        .context("embedding query")?;
    let q_vec = &query_embedding[0];

    let mut scored: Vec<(f32, &Chunk)> = store
        .chunks
        .iter()
        .map(|c| (cosine_similarity(q_vec, &c.embedding), c))
        .collect();
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

    let top: Vec<_> = scored.into_iter().take(top_k).collect();

    if top.is_empty() {
        println!("no results");
        return Ok(());
    }

    // Inject top chunks as context and ask the LLM
    let context: String = top
        .iter()
        .map(|(score, chunk)| format!("[score={score:.3} source={}]\n{}", chunk.source, chunk.text))
        .collect::<Vec<_>>()
        .join("\n\n---\n\n");

    let system_prompt = format!(
        "You are a helpful assistant. Use the following context to answer the user's question.\n\nContext:\n{context}"
    );

    let messages = vec![
        Message::system(system_prompt),
        Message::user(query_text),
    ];

    let provider = build_provider(&cfg.ai.provider, &cfg.ai.model)?;
    println!("query: {query_text}\n");
    let response = provider.chat(&messages).await?;
    println!("{response}");

    println!("\n── sources ──");
    for (score, chunk) in &top {
        println!("  {:.3}  {}", score, chunk.source);
    }

    Ok(())
}

pub async fn status() -> Result<()> {
    let store = load_store()?;
    let store_path = config::rag_store_path();

    println!("RAG store: {}", store_path.display());
    println!("Chunks:    {}", store.chunks.len());

    if !store.chunks.is_empty() {
        let sources: std::collections::HashSet<_> =
            store.chunks.iter().map(|c| &c.source).collect();
        println!("Sources:   {}", sources.len());
        for s in &sources {
            let count = store.chunks.iter().filter(|c| &&c.source == s).count();
            println!("  {count:>4} chunks  {s}");
        }
    }

    Ok(())
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn load_model() -> Result<TextEmbedding> {
    TextEmbedding::try_new(InitOptions::new(EmbeddingModel::AllMiniLML6V2))
        .context("loading fastembed model (AllMiniLML6V2)")
}

fn load_store() -> Result<RagStore> {
    let path = config::rag_store_path();
    if !path.exists() {
        return Ok(RagStore::default());
    }
    let bytes = std::fs::read(&path).with_context(|| format!("reading {}", path.display()))?;
    bincode::deserialize(&bytes).context("deserializing RAG store")
}

fn save_store(store: &RagStore) -> Result<()> {
    let path = config::rag_store_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let bytes = bincode::serialize(store).context("serializing RAG store")?;
    std::fs::write(&path, bytes)?;
    Ok(())
}

fn collect_files(path: &Path) -> Result<Vec<std::path::PathBuf>> {
    if path.is_file() {
        return Ok(vec![path.to_path_buf()]);
    }
    Ok(walkdir::WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter(|e| is_text_file(e.path()))
        .map(|e| e.path().to_path_buf())
        .collect())
}

fn is_text_file(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|e| e.to_str()),
        Some(
            "txt" | "md" | "rs" | "py" | "js" | "ts" | "go" | "toml" | "yaml" | "yml"
                | "json" | "sh" | "zsh" | "bash" | "conf" | "ini" | "env" | "sql"
        )
    )
}

fn chunk_text(text: &str, size: usize, overlap: usize) -> Vec<String> {
    let words: Vec<&str> = text.split_whitespace().collect();
    if words.is_empty() {
        return vec![];
    }
    let step = size.saturating_sub(overlap).max(1);
    let mut chunks = Vec::new();
    let mut start = 0;
    while start < words.len() {
        let end = (start + size).min(words.len());
        chunks.push(words[start..end].join(" "));
        start += step;
    }
    chunks
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }
    dot / (norm_a * norm_b)
}
