use crate::tui::app::App;
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};

pub fn render(app: &App, frame: &mut Frame) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(6),
            Constraint::Length(3),
            Constraint::Length(2),
        ])
        .split(area);

    // Title
    let title = Paragraph::new(Line::from(vec![
        Span::styled(" ai chat ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
    ]))
    .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    // Message history
    let visible_messages: Vec<ListItem> = app
        .ai_messages
        .iter()
        .skip(app.ai_scroll)
        .map(|(role, content)| {
            let (role_span, content_span) = match role.as_str() {
                "you" => (
                    Span::styled("you> ", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)),
                    Span::raw(content.clone()),
                ),
                "bot" => (
                    Span::styled("bot> ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)),
                    Span::raw(content.clone()),
                ),
                _ => (
                    Span::styled(format!("{role}> "), Style::default().fg(Color::DarkGray)),
                    Span::styled(content.clone(), Style::default().fg(Color::DarkGray)),
                ),
            };
            ListItem::new(Line::from(vec![role_span, content_span]))
        })
        .collect();

    let messages = List::new(visible_messages)
        .block(Block::default().borders(Borders::ALL).title(" Messages (↑/↓ scroll) "));
    frame.render_widget(messages, chunks[1]);

    // Input box
    let input_block = Block::default()
        .borders(Borders::ALL)
        .title(" Type message (Enter send, Esc clear) ")
        .border_style(Style::default().fg(Color::Cyan));
    let input = Paragraph::new(app.ai_input.as_str()).block(input_block);
    frame.render_widget(input, chunks[2]);

    // Help
    let help_text = if app.ai_waiting {
        "waiting for response..."
    } else {
        "Enter send  Esc clear/back  q back (empty input)"
    };
    let help = Paragraph::new(help_text).style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[3]);
}
