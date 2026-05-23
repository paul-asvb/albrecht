use clap::Parser;
use dialoguer::{Input, Select};
use std::process::Command;

#[derive(Parser)]
#[command(name = "volamar")]
#[command(version)]
#[command(about = "Create Farm frontend projects")]
struct Cli {
    /// Project name (directory to create)
    name: Option<String>,

    /// Framework template: react, vue, svelte, solid, preact, vanilla
    #[arg(short, long)]
    template: Option<String>,

    /// Package manager to use: npm, pnpm, yarn, bun
    #[arg(short, long)]
    pm: Option<String>,
}

const TEMPLATES: &[&str] = &["react", "vue", "svelte", "solid", "preact", "vanilla"];
const PKG_MANAGERS: &[&str] = &["npm", "pnpm", "yarn", "bun"];

fn main() {
    let cli = Cli::parse();

    let name: String = cli.name.unwrap_or_else(|| {
        Input::new()
            .with_prompt("Project name")
            .default("my-farm-app".to_string())
            .interact_text()
            .expect("failed to read project name")
    });

    let template: String = match cli.template {
        Some(t) => {
            if !TEMPLATES.contains(&t.as_str()) {
                eprintln!(
                    "Unknown template '{}'. Valid options: {}",
                    t,
                    TEMPLATES.join(", ")
                );
                std::process::exit(1);
            }
            t
        }
        None => {
            let idx = Select::new()
                .with_prompt("Select framework")
                .items(TEMPLATES)
                .default(0)
                .interact()
                .expect("failed to read template selection");
            TEMPLATES[idx].to_string()
        }
    };

    let pm: String = match cli.pm {
        Some(p) => p,
        None => {
            let available: Vec<&str> = PKG_MANAGERS
                .iter()
                .filter(|&&p| is_available(p))
                .copied()
                .collect();

            match available.as_slice() {
                [] => {
                    eprintln!("No package manager found. Install npm, pnpm, yarn, or bun.");
                    std::process::exit(1);
                }
                [only] => only.to_string(),
                _ => {
                    let idx = Select::new()
                        .with_prompt("Package manager")
                        .items(&available)
                        .default(0)
                        .interact()
                        .expect("failed to read package manager selection");
                    available[idx].to_string()
                }
            }
        }
    };

    println!("\nCreating '{}' ({}) with {}...\n", name, template, pm);

    let status = build_create_command(&pm, &name, &template)
        .status()
        .unwrap_or_else(|e| {
            eprintln!("Failed to run {}: {}", pm, e);
            std::process::exit(1);
        });

    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }

    println!("\nDone! Next steps:");
    println!("  cd {}", name);
    println!("  {} install", pm);
    println!("  {} start", pm);
}

fn build_create_command(pm: &str, name: &str, template: &str) -> Command {
    let mut cmd = Command::new(pm);
    match pm {
        // yarn create does not support the @version suffix
        "yarn" => {
            cmd.args(["create", "farm", name, "--template", template]);
        }
        _ => {
            cmd.args(["create", "farm@latest", name, "--template", template]);
        }
    }
    cmd
}

fn is_available(program: &str) -> bool {
    Command::new("which")
        .arg(program)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
