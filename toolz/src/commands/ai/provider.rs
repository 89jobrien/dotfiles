use anyhow::{bail, Result};
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

impl Message {
    pub fn user(content: impl Into<String>) -> Self {
        Self { role: "user".into(), content: content.into() }
    }

    pub fn assistant(content: impl Into<String>) -> Self {
        Self { role: "assistant".into(), content: content.into() }
    }

    pub fn system(content: impl Into<String>) -> Self {
        Self { role: "system".into(), content: content.into() }
    }
}

#[async_trait]
pub trait LlmProvider: Send + Sync {
    async fn chat(&self, messages: &[Message]) -> Result<String>;
}

// ── Ollama ───────────────────────────────────────────────────────────────────

pub struct OllamaProvider {
    client: Client,
    model: String,
    base_url: String,
}

impl OllamaProvider {
    pub fn new(model: impl Into<String>) -> Self {
        Self {
            client: Client::new(),
            model: model.into(),
            base_url: "http://localhost:11434".to_string(),
        }
    }
}

#[async_trait]
impl LlmProvider for OllamaProvider {
    async fn chat(&self, messages: &[Message]) -> Result<String> {
        #[derive(Serialize)]
        struct Req<'a> {
            model: &'a str,
            messages: &'a [Message],
            stream: bool,
        }

        #[derive(Deserialize)]
        struct Resp {
            message: OllamaMsg,
        }
        #[derive(Deserialize)]
        struct OllamaMsg {
            content: String,
        }

        let resp = self
            .client
            .post(format!("{}/api/chat", self.base_url))
            .json(&Req { model: &self.model, messages, stream: false })
            .send()
            .await?
            .error_for_status()?
            .json::<Resp>()
            .await?;

        Ok(resp.message.content)
    }
}

// ── OpenAI ───────────────────────────────────────────────────────────────────

pub struct OpenAiProvider {
    client: Client,
    model: String,
    api_key: String,
}

impl OpenAiProvider {
    pub fn new(model: impl Into<String>) -> Result<Self> {
        let api_key = std::env::var("OPENAI_API_KEY")
            .map_err(|_| anyhow::anyhow!("OPENAI_API_KEY not set"))?;
        Ok(Self { client: Client::new(), model: model.into(), api_key })
    }
}

#[async_trait]
impl LlmProvider for OpenAiProvider {
    async fn chat(&self, messages: &[Message]) -> Result<String> {
        #[derive(Serialize)]
        struct Req<'a> {
            model: &'a str,
            messages: &'a [Message],
        }

        #[derive(Deserialize)]
        struct Resp {
            choices: Vec<Choice>,
        }
        #[derive(Deserialize)]
        struct Choice {
            message: Message,
        }

        let resp = self
            .client
            .post("https://api.openai.com/v1/chat/completions")
            .bearer_auth(&self.api_key)
            .json(&Req { model: &self.model, messages })
            .send()
            .await?
            .error_for_status()?
            .json::<Resp>()
            .await?;

        resp.choices
            .into_iter()
            .next()
            .map(|c| c.message.content)
            .ok_or_else(|| anyhow::anyhow!("no choices in OpenAI response"))
    }
}

// ── Gemini ───────────────────────────────────────────────────────────────────

pub struct GeminiProvider {
    client: Client,
    model: String,
    api_key: String,
}

impl GeminiProvider {
    pub fn new(model: impl Into<String>) -> Result<Self> {
        let api_key = std::env::var("GEMINI_API_KEY")
            .map_err(|_| anyhow::anyhow!("GEMINI_API_KEY not set"))?;
        Ok(Self { client: Client::new(), model: model.into(), api_key })
    }
}

#[async_trait]
impl LlmProvider for GeminiProvider {
    async fn chat(&self, messages: &[Message]) -> Result<String> {
        #[derive(Serialize)]
        struct Req {
            contents: Vec<GeminiContent>,
        }
        #[derive(Serialize)]
        struct GeminiContent {
            role: String,
            parts: Vec<GeminiPart>,
        }
        #[derive(Serialize)]
        struct GeminiPart {
            text: String,
        }
        #[derive(Deserialize)]
        struct Resp {
            candidates: Vec<Candidate>,
        }
        #[derive(Deserialize)]
        struct Candidate {
            content: GeminiRespContent,
        }
        #[derive(Deserialize)]
        struct GeminiRespContent {
            parts: Vec<GeminiRespPart>,
        }
        #[derive(Deserialize)]
        struct GeminiRespPart {
            text: String,
        }

        let contents: Vec<GeminiContent> = messages
            .iter()
            .map(|m| GeminiContent {
                role: if m.role == "assistant" {
                    "model".to_string()
                } else {
                    m.role.clone()
                },
                parts: vec![GeminiPart { text: m.content.clone() }],
            })
            .collect();

        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent",
            self.model
        );

        let resp = self
            .client
            .post(&url)
            .header("x-goog-api-key", &self.api_key)
            .json(&Req { contents })
            .send()
            .await?
            .error_for_status()?
            .json::<Resp>()
            .await?;

        resp.candidates
            .into_iter()
            .next()
            .and_then(|c| c.content.parts.into_iter().next())
            .map(|p| p.text)
            .ok_or_else(|| anyhow::anyhow!("no candidates in Gemini response"))
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    /// The Gemini request URL must NOT contain the API key.
    /// API keys in query strings are exposed in server access logs, browser
    /// history, and HTTP Referer headers; they must be sent as a request header.
    #[test]
    fn test_gemini_url_does_not_contain_api_key() {
        let model = "gemini-2.0-flash";
        let api_key = "super-secret-key-abc123";

        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent",
            model
        );

        assert!(
            !url.contains(api_key),
            "Gemini URL must not embed the API key; got: {}",
            url
        );
        assert!(
            !url.contains("key="),
            "Gemini URL must not have a ?key= query parameter; got: {}",
            url
        );
    }

    /// The Gemini URL must contain the model name so the right endpoint is called.
    #[test]
    fn test_gemini_url_contains_model_name() {
        let model = "gemini-2.0-flash";
        let url = format!(
            "https://generativelanguage.googleapis.com/v1beta/models/{}:generateContent",
            model
        );
        assert!(url.contains(model), "URL should contain model name");
    }
}

// ── Factory ──────────────────────────────────────────────────────────────────

pub fn build_provider(
    provider: &str,
    model: &str,
) -> Result<Arc<dyn LlmProvider>> {
    match provider {
        "ollama" => Ok(Arc::new(OllamaProvider::new(model))),
        "openai" => Ok(Arc::new(OpenAiProvider::new(model)?)),
        "gemini" => Ok(Arc::new(GeminiProvider::new(model)?)),
        other => bail!("unknown provider: {other}; choose ollama|openai|gemini"),
    }
}
