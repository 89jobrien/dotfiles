use crate::tui::app::{App, LogsFilter};
use ratatui::{
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
    Frame,
};
use tracing::Level;

const TARGET_WIDTH: usize = 22;

fn level_style(level: Level) -> (char, &'static str, Color) {
    match level {
        Level::ERROR => ('●', "ERROR", Color::Red),
        Level::WARN  => ('●', "WARN ", Color::Yellow),
        Level::INFO  => ('●', "INFO ", Color::Cyan),
        Level::DEBUG => ('·', "DEBUG", Color::DarkGray),
        Level::TRACE => ('·', "TRACE", Color::Gray),
    }
}

pub fn render(app: &App, frame: &mut Frame) {
    let area = frame.area();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // header with level counts
            Constraint::Min(4),    // log entries
            Constraint::Length(2), // help bar
        ])
        .split(area);

    // Snapshot the buffer — hold the lock briefly, then release.
    let entries: Vec<_> = {
        let buf = app.log_buffer.lock().unwrap_or_else(|e| e.into_inner());
        buf.iter()
            .filter(|l| app.logs_filter.matches(l.level))
            .cloned()
            .collect()
    };

    let total = entries.len();
    let visible = chunks[1].height.saturating_sub(2) as usize; // subtract border rows
    let max_scroll = total.saturating_sub(visible);
    let scroll = app.logs_scroll.min(max_scroll);

    // Level counts across all entries (unfiltered for the stats bar).
    let all_buf = app.log_buffer.lock().unwrap_or_else(|e| e.into_inner());
    let (n_err, n_warn, n_info, n_debug) =
        all_buf.iter().fold((0u32, 0u32, 0u32, 0u32), |acc, l| match l.level {
            Level::ERROR => (acc.0 + 1, acc.1, acc.2, acc.3),
            Level::WARN  => (acc.0, acc.1 + 1, acc.2, acc.3),
            Level::INFO  => (acc.0, acc.1, acc.2 + 1, acc.3),
            _            => (acc.0, acc.1, acc.2, acc.3 + 1),
        });
    drop(all_buf);

    // ── Header ────────────────────────────────────────────────────────────
    let header_line = Line::from(vec![
        Span::styled("traces", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
        Span::raw("   "),
        Span::styled(format!("{n_err}E"), Style::default().fg(Color::Red).add_modifier(
            if n_err > 0 { Modifier::BOLD } else { Modifier::DIM },
        )),
        Span::raw("  "),
        Span::styled(format!("{n_warn}W"), Style::default().fg(Color::Yellow)),
        Span::raw("  "),
        Span::styled(format!("{n_info}I"), Style::default().fg(Color::Cyan)),
        Span::raw("  "),
        Span::styled(format!("{n_debug}D"), Style::default().fg(Color::DarkGray)),
        Span::raw(format!("   filter: ")),
        Span::styled(
            app.logs_filter.label(),
            Style::default().fg(filter_color(&app.logs_filter)).add_modifier(Modifier::BOLD),
        ),
    ]);

    let header = Paragraph::new(header_line)
        .block(Block::default().borders(Borders::ALL));
    frame.render_widget(header, chunks[0]);

    // ── Log entries ───────────────────────────────────────────────────────
    let items: Vec<ListItem> = entries
        .iter()
        .skip(scroll)
        .take(visible)
        .map(|l| {
            let (bullet, level_str, color) = level_style(l.level);
            let bold = if l.level == Level::ERROR { Modifier::BOLD } else { Modifier::empty() };

            let time = l.timestamp.format("%H:%M:%S").to_string();

            let target = if l.target.len() > TARGET_WIDTH {
                format!("{}…", &l.target[..TARGET_WIDTH.saturating_sub(1)])
            } else {
                format!("{:<width$}", l.target, width = TARGET_WIDTH)
            };

            ListItem::new(Line::from(vec![
                Span::styled(
                    format!(" {bullet} "),
                    Style::default().fg(color).add_modifier(bold),
                ),
                Span::styled(
                    level_str,
                    Style::default().fg(color).add_modifier(bold),
                ),
                Span::styled(" │ ", Style::default().fg(Color::DarkGray)),
                Span::styled(time, Style::default().fg(Color::DarkGray)),
                Span::styled(" │ ", Style::default().fg(Color::DarkGray)),
                Span::styled(target, Style::default().fg(Color::Gray)),
                Span::styled(" │ ", Style::default().fg(Color::DarkGray)),
                Span::raw(l.message.clone()),
            ]))
        })
        .collect();

    let scroll_hint = if total > visible {
        format!(" {}-{}/{} ", scroll + 1, (scroll + visible).min(total), total)
    } else {
        format!(" {total} entries ")
    };

    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(scroll_hint));
    frame.render_widget(list, chunks[1]);

    // ── Help bar ──────────────────────────────────────────────────────────
    let help = Paragraph::new(Line::from(vec![
        Span::styled("j/k", Style::default().fg(Color::White)),
        Span::styled(" scroll  ", Style::default().fg(Color::DarkGray)),
        Span::styled("f", Style::default().fg(Color::White)),
        Span::styled(" filter  ", Style::default().fg(Color::DarkGray)),
        Span::styled("c", Style::default().fg(Color::White)),
        Span::styled(" clear  ", Style::default().fg(Color::DarkGray)),
        Span::styled("G", Style::default().fg(Color::White)),
        Span::styled(" tail  ", Style::default().fg(Color::DarkGray)),
        Span::styled("q", Style::default().fg(Color::White)),
        Span::styled(" back", Style::default().fg(Color::DarkGray)),
    ]))
    .style(Style::default().fg(Color::DarkGray));
    frame.render_widget(help, chunks[2]);
}

fn filter_color(filter: &LogsFilter) -> Color {
    match filter {
        LogsFilter::All => Color::Cyan,
        LogsFilter::Info => Color::Blue,
        LogsFilter::Warn => Color::Yellow,
        LogsFilter::Error => Color::Red,
    }
}
