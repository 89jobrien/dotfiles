use super::app::{App, DbFocus, LogFocus, Screen};
use crossterm::event::{KeyCode, KeyEvent};

pub fn handle(app: &mut App, key: KeyEvent) {
    match &app.screen.clone() {
        Screen::Main => handle_main(app, key.code),
        Screen::Sys => handle_sys(app, key.code),
        Screen::Log => handle_log(app, key.code),
        Screen::AiChat => handle_ai(app, key.code),
        Screen::Db => handle_db(app, key.code),
    }
}

fn handle_main(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Char('q') | KeyCode::Char('Q') => app.should_quit = true,
        KeyCode::Up | KeyCode::Char('k') => {
            if app.main_selected > 0 {
                app.main_selected -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.main_selected + 1 < app.main_items.len() {
                app.main_selected += 1;
            }
        }
        KeyCode::Enter => match app.main_selected {
            0 => app.screen = Screen::Sys,
            1 => app.screen = Screen::Log,
            2 => app.screen = Screen::AiChat,
            3 => app.screen = Screen::Db,
            _ => {}
        },
        _ => {}
    }
}

fn handle_sys(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Char('q') | KeyCode::Esc => app.go_back(),
        KeyCode::Up | KeyCode::Char('k') => {
            if app.sys_selected > 0 {
                app.sys_selected -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.sys_selected + 1 < app.sys_items.len() {
                app.sys_selected += 1;
            }
        }
        KeyCode::Char(' ') => {
            if let Some(item) = app.sys_items.get_mut(app.sys_selected) {
                item.selected = !item.selected;
            }
        }
        KeyCode::Enter => {
            // Mark as "running" — actual execution happens via CLI
            app.sys_output.push("Run `toolz sys` in terminal to execute selected tasks.".to_string());
        }
        _ => {}
    }
}

fn handle_log(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Char('q') | KeyCode::Esc => {
            if app.log_focus == LogFocus::FileInput {
                app.go_back();
            } else {
                app.log_focus = LogFocus::FileInput;
            }
        }
        KeyCode::Tab => {
            app.log_focus = match app.log_focus {
                LogFocus::FileInput => LogFocus::PatternInput,
                LogFocus::PatternInput => LogFocus::Results,
                LogFocus::Results => LogFocus::FileInput,
            };
        }
        KeyCode::Up => {
            if app.log_focus == LogFocus::Results && app.log_scroll > 0 {
                app.log_scroll -= 1;
            }
        }
        KeyCode::Down => {
            if app.log_focus == LogFocus::Results {
                app.log_scroll = app.log_scroll.saturating_add(1);
            }
        }
        KeyCode::Enter => {
            if app.log_focus == LogFocus::PatternInput || app.log_focus == LogFocus::FileInput {
                app.log_results =
                    vec!["Run `toolz log analyze <file>` in terminal.".to_string()];
                app.log_focus = LogFocus::Results;
                app.log_scroll = 0;
            }
        }
        KeyCode::Backspace => match app.log_focus {
            LogFocus::FileInput => {
                app.log_file_input.pop();
            }
            LogFocus::PatternInput => {
                app.log_pattern_input.pop();
            }
            _ => {}
        },
        KeyCode::Char(c) => match app.log_focus {
            LogFocus::FileInput => app.log_file_input.push(c),
            LogFocus::PatternInput => app.log_pattern_input.push(c),
            _ => {}
        },
        _ => {}
    }
}

fn handle_ai(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Esc => {
            if app.ai_input.is_empty() {
                app.go_back();
            } else {
                app.ai_input.clear();
            }
        }
        KeyCode::Char('q') if app.ai_input.is_empty() => app.go_back(),
        KeyCode::Enter => {
            if !app.ai_input.is_empty() && !app.ai_waiting {
                let input = std::mem::take(&mut app.ai_input);
                app.ai_messages.push(("you".to_string(), input));
                app.ai_messages.push((
                    "tip".to_string(),
                    "Run `toolz ai chat` in a terminal for full AI chat with streaming.".to_string(),
                ));
                app.ai_scroll = app.ai_messages.len().saturating_sub(1);
            }
        }
        KeyCode::Backspace => {
            app.ai_input.pop();
        }
        KeyCode::Up => {
            app.ai_scroll = app.ai_scroll.saturating_sub(1);
        }
        KeyCode::Down => {
            app.ai_scroll = (app.ai_scroll + 1).min(app.ai_messages.len().saturating_sub(1));
        }
        KeyCode::Char(c) => {
            app.ai_input.push(c);
        }
        _ => {}
    }
}

fn handle_db(app: &mut App, code: KeyCode) {
    match code {
        KeyCode::Char('q') | KeyCode::Esc => {
            if app.db_focus == DbFocus::ConnectionList {
                app.go_back();
            } else {
                app.db_focus = DbFocus::ConnectionList;
            }
        }
        KeyCode::Tab => {
            app.db_focus = match app.db_focus {
                DbFocus::ConnectionList => DbFocus::QueryInput,
                DbFocus::QueryInput => DbFocus::Results,
                DbFocus::Results => DbFocus::ConnectionList,
            };
        }
        KeyCode::Up | KeyCode::Char('k') => {
            if app.db_focus == DbFocus::ConnectionList && app.db_selected > 0 {
                app.db_selected -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            if app.db_focus == DbFocus::ConnectionList
                && app.db_selected + 1 < app.db_connections.len()
            {
                app.db_selected += 1;
            }
        }
        KeyCode::Enter => {
            if app.db_focus == DbFocus::QueryInput && !app.db_query_input.is_empty() {
                app.db_results = vec![
                    format!("Query: {}", app.db_query_input),
                    "Run `toolz db query <name> '<sql>'` in terminal for actual results.".to_string(),
                ];
                app.db_focus = DbFocus::Results;
            }
        }
        KeyCode::Backspace => {
            if app.db_focus == DbFocus::QueryInput {
                app.db_query_input.pop();
            }
        }
        KeyCode::Char(c) => {
            if app.db_focus == DbFocus::QueryInput {
                app.db_query_input.push(c);
            }
        }
        _ => {}
    }
}
