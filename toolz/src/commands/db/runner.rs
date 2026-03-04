use super::config::get;
use anyhow::{bail, Result};
use chrono::Local;
use std::process::Command;

pub fn connect(name: &str) -> Result<()> {
    let conn = get(name)?;
    let cli = driver_cli(&conn.driver)?;

    check_cli(cli)?;

    let mut cmd = match conn.driver.as_str() {
        "postgres" | "postgresql" => {
            let mut c = Command::new("psql");
            c.arg(&conn.url);
            c
        }
        "mysql" => {
            let mut c = Command::new("mysql");
            c.arg("--url").arg(&conn.url);
            c
        }
        "sqlite" => {
            let mut c = Command::new("sqlite3");
            // sqlite URL is just a file path (strip sqlite:// prefix)
            let path = conn.url.trim_start_matches("sqlite://");
            c.arg(path);
            c
        }
        other => bail!("unsupported driver: {other}"),
    };

    let status = cmd.status()?;
    if !status.success() {
        bail!("{cli} exited with {}", status.code().unwrap_or(-1));
    }
    Ok(())
}

pub fn query(name: &str, sql: &str) -> Result<()> {
    let conn = get(name)?;
    let cli = driver_cli(&conn.driver)?;

    check_cli(cli)?;

    let output = match conn.driver.as_str() {
        "postgres" | "postgresql" => Command::new("psql")
            .args([&conn.url, "-c", sql])
            .output()?,
        "mysql" => Command::new("mysql")
            .args(["--url", &conn.url, "-e", sql])
            .output()?,
        "sqlite" => {
            let path = conn.url.trim_start_matches("sqlite://");
            Command::new("sqlite3").args([path, sql]).output()?
        }
        other => bail!("unsupported driver: {other}"),
    };

    print!("{}", String::from_utf8_lossy(&output.stdout));
    if !output.stderr.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
    }
    if !output.status.success() {
        bail!("{cli} exited with {}", output.status.code().unwrap_or(-1));
    }
    Ok(())
}

pub fn backup(name: &str, output: Option<&str>) -> Result<()> {
    let conn = get(name)?;

    let timestamp = Local::now().format("%Y%m%d_%H%M%S");
    let default_out = format!("{name}_{timestamp}.sql");
    let out_file = output.unwrap_or(&default_out);

    match conn.driver.as_str() {
        "postgres" | "postgresql" => {
            check_cli("pg_dump")?;
            let status = Command::new("pg_dump")
                .args([&conn.url, "-f", out_file])
                .status()?;
            if !status.success() {
                bail!("pg_dump failed");
            }
        }
        "mysql" => {
            check_cli("mysqldump")?;
            let output_bytes = Command::new("mysqldump")
                .args(["--url", &conn.url])
                .output()?;
            if !output_bytes.status.success() {
                bail!("mysqldump failed: {}", String::from_utf8_lossy(&output_bytes.stderr));
            }
            std::fs::write(out_file, output_bytes.stdout)?;
        }
        "sqlite" => {
            let path = conn.url.trim_start_matches("sqlite://");
            std::fs::copy(path, out_file)?;
        }
        other => bail!("unsupported driver: {other}"),
    }

    println!("backup written to {out_file}");
    Ok(())
}

fn driver_cli(driver: &str) -> Result<&'static str> {
    match driver {
        "postgres" | "postgresql" => Ok("psql"),
        "mysql" => Ok("mysql"),
        "sqlite" => Ok("sqlite3"),
        other => bail!("unsupported driver: {other}"),
    }
}

fn check_cli(cli: &str) -> Result<()> {
    if Command::new("which").arg(cli).output().map(|o| o.status.success()).unwrap_or(false) {
        Ok(())
    } else {
        bail!("{cli} not found in PATH; install it first")
    }
}
