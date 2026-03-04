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
            Constraint::Percentage(50),
            Constraint::Min(4),
            Constraint::Length(2),
        ])
        .split(area);

    // Title
    let title = Paragraph::new(Line::from(vec![
        Span::styled(" sys ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::raw("system maintenance"),
    ]))
    .block(Block::default().borders(Borders::ALL));
    frame.render_widget(title, chunks[0]);

    // Task list
    let items: Vec<ListItem> = app
        .sys_items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let check = if item.selected { "[x]" } else { "[ ]" };
            let status = match item.done {
                Some(true) => " ✓",
                Some(false) => " ✗",
                None => "",
            };
            let line = format!("  {check} {}{}", item.label, status);
            let style = if i == app.sys_selected {
                Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)
            } else if item.selected {
                Style::default().fg(Color::Green)
            } else {
                Style::default().fg(Color::DarkGray)
            };
            ListItem::new(line).style(style)
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(app.sys_selected));
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Tasks "));
    frame.render_stateful_widget(list, chunks[1], &mut state);

    // Output area
    let output_text: Vec<Line> = app
        .sys_output
        .iter()
        .map(|s| Line::from(s.as_str()))
        .collect();
    let output = Paragraph::new(output_text)
        .block(Block::default().borders(Borders::ALL).title(" Output "))
        .wrap(ratatui::widgets::Wrap { trim: false });
    frame.render_widget(output, chunks[2]);

    // Help
    let help = Paragraph::new("↑/↓ navigate  Space toggle  Enter run  Esc/q back")
        .style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[3]);
}
