use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
pub struct Config {
    #[serde(default)]
    pub ai: AiConfig,
    #[serde(default)]
    pub db: DbConfig,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct AiConfig {
    pub provider: String,
    pub model: String,
}

impl Default for AiConfig {
    fn default() -> Self {
        Self {
            provider: "ollama".to_string(),
            model: "llama3.2:3b".to_string(),
        }
    }
}

#[derive(Debug, Deserialize, Serialize, Default, Clone)]
pub struct DbConfig {
    #[serde(default)]
    pub connections: Vec<DbConnection>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct DbConnection {
    pub name: String,
    pub driver: String,
    pub url: String,
}

pub fn config_dir() -> PathBuf {
    dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".config"))
        .join("toolz")
}

pub fn config_path() -> PathBuf {
    config_dir().join("config.toml")
}

pub fn rag_store_path() -> PathBuf {
    config_dir().join("rag.bin")
}

pub fn load() -> anyhow::Result<Config> {
    let path = config_path();
    if !path.exists() {
        return Ok(Config::default());
    }
    let contents =
        std::fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
    toml::from_str(&contents).context("parsing config.toml")
}

pub fn save(config: &Config) -> anyhow::Result<()> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
        #[cfg(unix)]
        std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
    }
    let contents = toml::to_string_pretty(config)?;
    let mut file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&path)
        .with_context(|| format!("opening {} for write", path.display()))?;
    file.write_all(contents.as_bytes())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Exercise the secure-write path directly (without routing through
    /// config_path / dirs::config_dir) so the test is portable and does not
    /// clobber real config state.
    #[cfg(unix)]
    fn write_config_to(path: &std::path::Path, config: &Config) -> anyhow::Result<()> {
        use std::os::unix::fs::PermissionsExt;

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
            std::fs::set_permissions(parent, std::fs::Permissions::from_mode(0o700))?;
        }
        let contents = toml::to_string_pretty(config)?;
        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)
            .with_context(|| format!("opening {} for write", path.display()))?;
        file.write_all(contents.as_bytes())?;
        Ok(())
    }

    #[test]
    #[cfg(unix)]
    fn test_save_config_file_mode_is_0600() {
        use std::os::unix::fs::PermissionsExt;

        let dir = std::env::temp_dir().join(format!("toolz-test-{}", std::process::id()));
        let path = dir.join("config.toml");

        // Remove leftover from a previous run if present
        let _ = std::fs::remove_dir_all(&dir);

        let config = Config::default();
        write_config_to(&path, &config).expect("write_config_to should succeed");

        let meta = std::fs::metadata(&path).expect("metadata");
        let mode = meta.permissions().mode() & 0o777;

        // Cleanup before asserting so we don't leak the temp dir on failure
        let _ = std::fs::remove_dir_all(&dir);

        assert_eq!(mode, 0o600, "file mode should be 0600, got {:o}", mode);
    }
}
