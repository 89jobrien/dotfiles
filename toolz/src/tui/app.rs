/// Active screen in the TUI.
#[derive(Debug, Clone, PartialEq)]
pub enum Screen {
    Main,
    Sys,
    Log,
    AiChat,
    Db,
}

/// Shared application state threaded through all screens.
pub struct App {
    pub screen: Screen,
    pub should_quit: bool,

    // Main menu
    pub main_selected: usize,
    pub main_items: Vec<&'static str>,

    // Sys screen
    pub sys_selected: usize,
    pub sys_items: Vec<SysItem>,
    pub sys_output: Vec<String>,

    // Log screen
    pub log_file_input: String,
    pub log_pattern_input: String,
    pub log_results: Vec<String>,
    pub log_focus: LogFocus,
    pub log_scroll: usize,

    // AI chat screen
    pub ai_input: String,
    pub ai_messages: Vec<(String, String)>, // (role, content)
    pub ai_scroll: usize,
    pub ai_waiting: bool,

    // DB screen
    pub db_connections: Vec<String>,
    pub db_selected: usize,
    pub db_query_input: String,
    pub db_results: Vec<String>,
    pub db_focus: DbFocus,
}

#[derive(Debug, Clone, PartialEq)]
pub enum LogFocus {
    FileInput,
    PatternInput,
    Results,
}

#[derive(Debug, Clone, PartialEq)]
pub enum DbFocus {
    ConnectionList,
    QueryInput,
    Results,
}

pub struct SysItem {
    pub label: &'static str,
    pub selected: bool,
    pub done: Option<bool>, // None = not run, Some(true/false) = ok/failed
}

impl App {
    pub fn new() -> Self {
        let cfg = crate::config::load().unwrap_or_default();
        let db_connections = cfg
            .db
            .connections
            .iter()
            .map(|c| format!("{} ({})", c.name, c.driver))
            .collect();

        Self {
            screen: Screen::Main,
            should_quit: false,
            main_selected: 0,
            main_items: vec!["sys  — system maintenance", "log  — log analysis", "ai   — AI chat / RAG", "db   — database management"],
            sys_selected: 0,
            sys_items: vec![
                SysItem { label: "brew", selected: true, done: None },
                SysItem { label: "docker", selected: true, done: None },
                SysItem { label: "git gc", selected: true, done: None },
                SysItem { label: "cargo sweep", selected: true, done: None },
                SysItem { label: "cache clean", selected: true, done: None },
            ],
            sys_output: Vec::new(),
            log_file_input: String::new(),
            log_pattern_input: String::new(),
            log_results: Vec::new(),
            log_focus: LogFocus::FileInput,
            log_scroll: 0,
            ai_input: String::new(),
            ai_messages: Vec::new(),
            ai_scroll: 0,
            ai_waiting: false,
            db_connections,
            db_selected: 0,
            db_query_input: String::new(),
            db_results: Vec::new(),
            db_focus: DbFocus::ConnectionList,
        }
    }

    pub fn go_back(&mut self) {
        self.screen = Screen::Main;
    }
}
