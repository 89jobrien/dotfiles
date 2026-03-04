pub mod ai_chat;
pub mod db;
pub mod log;
pub mod main_screen;
pub mod sys;

use crate::tui::app::{App, Screen};
use ratatui::Frame;

pub fn render(app: &App, frame: &mut Frame) {
    match &app.screen {
        Screen::Main => main_screen::render(app, frame),
        Screen::Sys => sys::render(app, frame),
        Screen::Log => log::render(app, frame),
        Screen::AiChat => ai_chat::render(app, frame),
        Screen::Db => db::render(app, frame),
    }
}
