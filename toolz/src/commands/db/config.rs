use crate::config::{self, DbConnection};
use anyhow::{bail, Result};

pub fn list() -> Result<()> {
    let cfg = config::load()?;
    if cfg.db.connections.is_empty() {
        println!("no connections configured");
        println!("add one with: toolz db add <name> <driver> <url>");
        return Ok(());
    }
    println!("{:<20} {:<10} {}", "NAME", "DRIVER", "URL");
    println!("{}", "─".repeat(60));
    for conn in &cfg.db.connections {
        let masked = mask_url(&conn.url);
        println!("{:<20} {:<10} {}", conn.name, conn.driver, masked);
    }
    Ok(())
}

pub fn add(name: &str, driver: &str, url: &str) -> Result<()> {
    validate_driver(driver)?;
    let mut cfg = config::load()?;
    if cfg.db.connections.iter().any(|c| c.name == name) {
        bail!("connection '{name}' already exists; remove it first or choose a different name");
    }
    cfg.db.connections.push(DbConnection {
        name: name.to_string(),
        driver: driver.to_string(),
        url: url.to_string(),
    });
    config::save(&cfg)?;
    println!("added connection '{name}'");
    Ok(())
}

pub fn get(name: &str) -> Result<DbConnection> {
    let cfg = config::load()?;
    cfg.db
        .connections
        .into_iter()
        .find(|c| c.name == name)
        .ok_or_else(|| anyhow::anyhow!("connection '{name}' not found; run `toolz db list`"))
}

fn validate_driver(driver: &str) -> Result<()> {
    match driver {
        "postgres" | "postgresql" | "mysql" | "sqlite" => Ok(()),
        other => bail!("unsupported driver: {other}; choose postgres|mysql|sqlite"),
    }
}

fn mask_url(url: &str) -> String {
    // Replace password in postgres://user:pass@host/db
    if let Some(at_pos) = url.find('@') {
        if let Some(colon_pos) = url[..at_pos].rfind(':') {
            let scheme_end = url.find("://").map(|p| p + 3).unwrap_or(0);
            if colon_pos > scheme_end {
                let masked = format!("{}:****{}", &url[..colon_pos], &url[at_pos..]);
                return masked;
            }
        }
    }
    url.to_string()
}
