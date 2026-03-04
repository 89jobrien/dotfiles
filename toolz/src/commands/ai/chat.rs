use super::provider::{build_provider, Message};
use crate::config;
use anyhow::Result;
use std::io::{self, Write};

pub async fn run(provider_override: Option<String>, model_override: Option<String>) -> Result<()> {
    let cfg = config::load()?;
    let provider_name = provider_override
        .as_deref()
        .unwrap_or(&cfg.ai.provider)
        .to_string();
    let model = model_override
        .as_deref()
        .unwrap_or(&cfg.ai.model)
        .to_string();

    let provider = build_provider(&provider_name, &model)?;

    println!("toolz ai chat  [{provider_name}/{model}]  (type 'exit' or Ctrl-D to quit)\n");

    let mut history: Vec<Message> = Vec::new();
    let stdin = io::stdin();

    loop {
        print!("\x1b[1;36myou>\x1b[0m ");
        io::stdout().flush()?;

        let mut input = String::new();
        match stdin.read_line(&mut input) {
            Ok(0) => break, // EOF / Ctrl-D
            Ok(_) => {}
            Err(e) => return Err(e.into()),
        }

        let input = input.trim().to_string();
        if input.is_empty() {
            continue;
        }
        if input == "exit" || input == "quit" {
            break;
        }

        history.push(Message::user(&input));

        print!("\x1b[1;33mbot>\x1b[0m ");
        io::stdout().flush()?;

        match provider.chat(&history).await {
            Ok(response) => {
                println!("{response}");
                println!();
                history.push(Message::assistant(&response));
            }
            Err(e) => {
                eprintln!("\x1b[31merror:\x1b[0m {e}");
                // Remove the user message so context stays clean
                history.pop();
            }
        }
    }

    println!("\nbye.");
    Ok(())
}
