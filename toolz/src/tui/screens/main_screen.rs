use crate::tui::app::App;
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame,
};

pub fn render(app: &App, frame: &mut Frame) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(6),
            Constraint::Length(2),
        ])
        .split(area);

    // Title
    let title = Paragraph::new(Line::from(vec![
        Span::styled("toolz", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::raw("  personal swiss-army CLI"),
    ]))
    .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    // Command list
    let items: Vec<ListItem> = app
        .main_items
        .iter()
        .enumerate()
        .map(|(i, label)| {
            let style = if i == app.main_selected {
                Style::default()
                    .fg(Color::Black)
                    .bg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };
            ListItem::new(format!("  {label}  ")).style(style)
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(app.main_selected));

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Commands "));
    frame.render_stateful_widget(list, chunks[1], &mut state);

    // Help bar
    let help = Paragraph::new("↑/↓ navigate  Enter select  q quit")
        .style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[2]);
}
