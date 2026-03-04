use crate::tui::app::{App, LogFocus};
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn render(app: &App, frame: &mut Frame) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);

    // Title
    let title = Paragraph::new(" log  analysis")
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    // File input
    let file_style = if app.log_focus == LogFocus::FileInput {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let file_block = Block::default()
        .borders(Borders::ALL)
        .title(" File path ")
        .border_style(file_style);
    let file_input = Paragraph::new(app.log_file_input.as_str()).block(file_block);
    frame.render_widget(file_input, chunks[1]);

    // Pattern input
    let pat_style = if app.log_focus == LogFocus::PatternInput {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let pat_block = Block::default()
        .borders(Borders::ALL)
        .title(" Pattern (optional) ")
        .border_style(pat_style);
    let pat_input = Paragraph::new(app.log_pattern_input.as_str()).block(pat_block);
    frame.render_widget(pat_input, chunks[2]);

    // Results
    let results_style = if app.log_focus == LogFocus::Results {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let items: Vec<ListItem> = app
        .log_results
        .iter()
        .skip(app.log_scroll)
        .map(|s| ListItem::new(s.as_str()))
        .collect();
    let results = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(" Results ")
                .border_style(results_style),
        );
    frame.render_widget(results, chunks[3]);

    // Help
    let help = Paragraph::new("Tab focus  Enter run  ↑/↓ scroll results  Esc back")
        .style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[4]);
}
