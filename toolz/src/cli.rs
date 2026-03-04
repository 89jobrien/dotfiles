use clap::{Args, Parser, Subcommand};

#[derive(Parser)]
#[command(name = "toolz", version, about = "Personal swiss-army CLI")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand)]
pub enum Commands {
    /// System maintenance (brew, docker, git, cargo, cache)
    Sys(SysArgs),
    /// Log analysis
    Log {
        #[command(subcommand)]
        action: LogAction,
    },
    /// AI chat and RAG
    Ai {
        #[command(subcommand)]
        action: AiAction,
    },
    /// Database management
    Db {
        #[command(subcommand)]
        action: DbAction,
    },
}

#[derive(Args)]
pub struct SysArgs {
    /// Run brew update + cleanup
    #[arg(long)]
    pub brew: bool,
    /// Run docker image/container prune
    #[arg(long)]
    pub docker: bool,
    /// Run git gc in ~/dev repos
    #[arg(long)]
    pub git: bool,
    /// Run cargo sweep on ~/dev
    #[arg(long)]
    pub cargo: bool,
    /// Clean npm/uv/system caches
    #[arg(long)]
    pub cache: bool,
    /// Print what would run without executing
    #[arg(long)]
    pub dry_run: bool,
}

impl SysArgs {
    /// True if no specific task flags were set (run all by default).
    pub fn run_all(&self) -> bool {
        !self.brew && !self.docker && !self.git && !self.cargo && !self.cache
    }
}

#[derive(Subcommand)]
pub enum LogAction {
    /// Show summary stats for a log file
    Analyze {
        /// Path to the log file
        file: String,
    },
    /// Extract lines matching error/warn patterns
    Errors {
        /// Path to the log file
        file: String,
        /// Regex pattern (default: error|warn|ERRO|WARN)
        #[arg(short, long)]
        pattern: Option<String>,
    },
}

#[derive(Subcommand)]
pub enum AiAction {
    /// Interactive REPL chat
    Chat {
        /// Provider override (openai|gemini|ollama)
        #[arg(long)]
        provider: Option<String>,
        /// Model override
        #[arg(long)]
        model: Option<String>,
    },
    /// RAG operations
    Rag {
        #[command(subcommand)]
        action: RagAction,
    },
}

#[derive(Subcommand)]
pub enum RagAction {
    /// Add a file to the RAG store
    Add {
        /// Path to file or directory
        path: String,
    },
    /// Query the RAG store
    Query {
        /// Natural language query
        query: String,
        /// Number of results
        #[arg(short, long, default_value_t = 5)]
        top_k: usize,
    },
    /// Show RAG store stats
    Status,
}

#[derive(Subcommand)]
pub enum DbAction {
    /// List configured connections
    List,
    /// Open an interactive shell for a connection
    Connect {
        /// Connection name
        name: String,
    },
    /// Run a SQL query against a connection
    Query {
        /// Connection name
        name: String,
        /// SQL statement
        sql: String,
    },
    /// Add a named connection
    Add {
        /// Connection name
        name: String,
        /// Driver (postgres|mysql|sqlite)
        driver: String,
        /// Connection URL
        url: String,
    },
    /// Backup a database
    Backup {
        /// Connection name
        name: String,
        /// Output file (optional, defaults to name-timestamp.sql)
        #[arg(short, long)]
        output: Option<String>,
    },
}
