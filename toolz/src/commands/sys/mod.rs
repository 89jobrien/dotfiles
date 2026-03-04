pub mod brew;
pub mod cache;
pub mod cargo;
pub mod docker;
pub mod git;

use crate::cli::SysArgs;
use crate::output;
use anyhow::Result;

pub async fn run(args: SysArgs) -> Result<()> {
    let all = args.run_all();

    if all || args.brew {
        output::section("Brew");
        brew::run(args.dry_run)?;
    }
    if all || args.docker {
        output::section("Docker");
        docker::run(args.dry_run)?;
    }
    if all || args.git {
        output::section("Git");
        git::run(args.dry_run)?;
    }
    if all || args.cargo {
        output::section("Cargo");
        cargo::run(args.dry_run)?;
    }
    if all || args.cache {
        output::section("Cache");
        cache::run(args.dry_run)?;
    }

    output::ok("sys maintenance complete");
    Ok(())
}
