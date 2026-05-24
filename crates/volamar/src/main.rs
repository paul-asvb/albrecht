use clap::{Parser, Subcommand};
use volamar_core::{create_project, run_dev_all, run_script};

#[derive(Parser)]
#[command(name = "volamar")]
#[command(version)]
#[command(about = "Create and manage Farm frontend projects")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Project name (directory to create)
    name: Option<String>,

    /// Framework template: react, vue, svelte, solid, preact, vanilla
    #[arg(short, long)]
    template: Option<String>,

    /// Package manager to use: npm, pnpm, yarn, bun
    #[arg(short, long)]
    pm: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the Farm dev server for all Farm apps found under DIR
    Dev {
        /// Root directory to search for Farm apps
        #[arg(default_value = ".")]
        dir: String,
    },
    /// Build the Farm project
    Build {
        /// Project directory
        #[arg(default_value = ".")]
        dir: String,
    },
    /// Preview the built project
    Preview {
        /// Project directory
        #[arg(default_value = ".")]
        dir: String,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Dev { dir }) => run_dev_all(&dir),
        Some(Commands::Build { dir }) => run_script("build", &dir),
        Some(Commands::Preview { dir }) => run_script("preview", &dir),
        None => create_project(cli.name, cli.template, cli.pm),
    }
}
