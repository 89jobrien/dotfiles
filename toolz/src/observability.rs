use chrono::{DateTime, Local};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Layer};

/// Maximum log lines kept in the TUI ring buffer.
pub const LOG_CAPACITY: usize = 500;

pub type LogBuffer = Arc<Mutex<VecDeque<LogLine>>>;

#[derive(Clone, Debug)]
pub struct LogLine {
    pub timestamp: DateTime<Local>,
    pub level: tracing::Level,
    pub target: String,
    pub message: String,
}

/// tracing-subscriber Layer that pushes events into the TUI ring buffer.
pub struct TuiLayer {
    buffer: LogBuffer,
}

impl TuiLayer {
    fn new(buffer: LogBuffer) -> Self {
        Self { buffer }
    }
}

struct MsgVisitor(String);

impl tracing::field::Visit for MsgVisitor {
    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.0 = value.to_string();
        }
    }

    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0 = format!("{value:?}");
        }
    }
}

impl<S> Layer<S> for TuiLayer
where
    S: tracing::Subscriber,
{
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        let meta = event.metadata();
        let mut visitor = MsgVisitor(String::new());
        event.record(&mut visitor);

        let line = LogLine {
            timestamp: Local::now(),
            level: *meta.level(),
            target: meta.target().to_string(),
            message: visitor.0,
        };

        if let Ok(mut buf) = self.buffer.lock() {
            buf.push_back(line);
            if buf.len() > LOG_CAPACITY {
                buf.pop_front();
            }
        }
    }
}

/// Opaque guard — keep alive for the process lifetime to flush file logs on exit.
#[allow(dead_code)]
pub struct TracingGuard(tracing_appender::non_blocking::WorkerGuard);

fn log_dir() -> std::path::PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("toolz")
}

/// Initialize tracing for TUI mode.
///
/// - File: daily rolling log to `{data_local_dir}/toolz/toolz.log`
/// - TUI: ring buffer via `TuiLayer` (no stdout/stderr output — would corrupt the terminal)
///
/// Returns the shared `LogBuffer` for the TUI to display and a guard to keep alive.
pub fn init_tui() -> anyhow::Result<(LogBuffer, TracingGuard)> {
    let buffer: LogBuffer = Arc::new(Mutex::new(VecDeque::with_capacity(LOG_CAPACITY)));

    let log_dir = log_dir();
    std::fs::create_dir_all(&log_dir)?;

    let file_appender = tracing_appender::rolling::daily(&log_dir, "toolz.log");
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(non_blocking)
        .with_ansi(false);

    let tui_layer = TuiLayer::new(Arc::clone(&buffer));

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("debug"));

    tracing_subscriber::registry()
        .with(filter)
        .with(file_layer)
        .with(tui_layer)
        .init();

    Ok((buffer, TracingGuard(guard)))
}

/// Initialize tracing for CLI (command) mode.
///
/// - File: daily rolling log (same path as TUI mode)
/// - Stderr: human-readable compact output, respects `RUST_LOG`
pub fn init_cli() -> anyhow::Result<TracingGuard> {
    let log_dir = log_dir();
    std::fs::create_dir_all(&log_dir)?;

    let file_appender = tracing_appender::rolling::daily(&log_dir, "toolz.log");
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(non_blocking)
        .with_ansi(false);

    let stderr_layer = tracing_subscriber::fmt::layer()
        .with_writer(std::io::stderr)
        .with_ansi(true)
        .compact();

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::registry()
        .with(filter)
        .with(file_layer)
        .with(stderr_layer)
        .init();

    Ok(TracingGuard(guard))
}
