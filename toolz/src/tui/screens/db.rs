use crate::tui::app::{App, DbFocus};
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame,
};

pub fn render(app: &App, frame: &mut Frame) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Percentage(30),
            Constraint::Length(3),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);

    // Title
    let title = Paragraph::new(" db  database management")
        .style(Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
        .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    // Connection list
    let conn_style = if app.db_focus == DbFocus::ConnectionList {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let conn_items: Vec<ListItem> = if app.db_connections.is_empty() {
        vec![ListItem::new("  (no connections — run `toolz db add` to add one)")
            .style(Style::default().fg(Color::DarkGray))]
    } else {
        app.db_connections
            .iter()
            .enumerate()
            .map(|(i, name)| {
                let style = if i == app.db_selected && app.db_focus == DbFocus::ConnectionList {
                    Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)
                } else {
                    Style::default()
                };
                ListItem::new(format!("  {name}  ")).style(style)
            })
            .collect()
    };

    let mut conn_state = ListState::default();
    conn_state.select(Some(app.db_selected));
    let conn_list = List::new(conn_items)
        .block(Block::default().borders(Borders::ALL).title(" Connections ").border_style(conn_style));
    frame.render_stateful_widget(conn_list, chunks[1], &mut conn_state);

    // Query input
    let query_style = if app.db_focus == DbFocus::QueryInput {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let query = Paragraph::new(app.db_query_input.as_str())
        .block(Block::default().borders(Borders::ALL).title(" SQL Query ").border_style(query_style));
    frame.render_widget(query, chunks[2]);

    // Results
    let results_style = if app.db_focus == DbFocus::Results {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };
    let result_items: Vec<ListItem> = app
        .db_results
        .iter()
        .map(|s| ListItem::new(s.as_str()))
        .collect();
    let results = List::new(result_items)
        .block(Block::default().borders(Borders::ALL).title(" Results ").border_style(results_style));
    frame.render_widget(results, chunks[3]);

    // Help
    let help = Paragraph::new("Tab focus  ↑/↓ select conn  Enter run query  Esc/q back")
        .style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[4]);
}
