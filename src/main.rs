use clap::{Parser, Subcommand};
use dialoguer::{Input, Select};
use std::path::{Path, PathBuf};
use std::process::Command;

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

const TEMPLATES: &[&str] = &["react", "vue", "svelte", "solid", "preact", "vanilla"];
const PKG_MANAGERS: &[&str] = &["npm", "pnpm", "yarn", "bun"];
const SKIP_DIRS: &[&str] = &[
    "node_modules",
    "target",
    "dist",
    "build",
    ".farm",
    ".git",
    ".cache",
];

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Dev { dir }) => run_dev_all(&dir),
        Some(Commands::Build { dir }) => run_script("build", &dir),
        Some(Commands::Preview { dir }) => run_script("preview", &dir),
        None => create_project(cli.name, cli.template, cli.pm),
    }
}

fn run_dev_all(dir: &str) {
    let root = Path::new(dir);
    let apps = find_farm_apps(root);

    if apps.is_empty() {
        eprintln!("No Farm projects found in '{}'.", dir);
        std::process::exit(1);
    }

    println!("Starting {} Farm app(s):", apps.len());

    let mut children = Vec::new();

    for app_dir in &apps {
        let pm = match detect_pm(app_dir) {
            Some(pm) => pm,
            None => {
                eprintln!(
                    "  {} [skipped — no lock file found]",
                    app_dir.display()
                );
                continue;
            }
        };

        println!("  {} [{}]", app_dir.display(), pm);

        let child = Command::new(pm)
            .args(["run", "dev"])
            .current_dir(app_dir)
            .spawn()
            .unwrap_or_else(|e| {
                eprintln!("Failed to start '{}': {}", app_dir.display(), e);
                std::process::exit(1);
            });

        children.push(child);
    }

    for child in &mut children {
        let _ = child.wait();
    }
}

fn find_farm_apps(root: &Path) -> Vec<PathBuf> {
    let mut apps = Vec::new();
    collect_farm_apps(root, &mut apps, 0);
    apps
}

fn collect_farm_apps(dir: &Path, apps: &mut Vec<PathBuf>, depth: u32) {
    if depth > 6 {
        return;
    }

    if let Some(name) = dir.file_name() {
        let name = name.to_string_lossy();
        if SKIP_DIRS.contains(&name.as_ref()) || name.starts_with('.') {
            return;
        }
    }

    let is_farm_app = ["farm.config.ts", "farm.config.js", "farm.config.mjs"]
        .iter()
        .any(|f| dir.join(f).exists())
        && dir.join("package.json").exists();

    if is_farm_app {
        apps.push(dir.to_path_buf());
        return;
    }

    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_farm_apps(&path, apps, depth + 1);
            }
        }
    }
}

fn run_script(script: &str, dir: &str) {
    let path = Path::new(dir);
    let pm = detect_pm(path).unwrap_or_else(|| {
        eprintln!("Could not detect package manager in '{}'.", dir);
        std::process::exit(1);
    });

    let status = Command::new(pm)
        .args(["run", script])
        .current_dir(path)
        .status()
        .unwrap_or_else(|e| {
            eprintln!("Failed to run {}: {}", pm, e);
            std::process::exit(1);
        });

    if !status.success() {
        std::process::exit(status.code().unwrap_or(1));
    }
}

fn detect_pm(dir: &Path) -> Option<&'static str> {
    if dir.join("pnpm-lock.yaml").exists() {
        Some("pnpm")
    } else if dir.join("bun.lockb").exists() {
        Some("bun")
    } else if dir.join("yarn.lock").exists() {
        Some("yarn")
    } else if dir.join("package-lock.json").exists() {
        Some("npm")
    } else {
        None
    }
}

fn create_project(name: Option<String>, template: Option<String>, pm: Option<String>) {
    let name: String = name.unwrap_or_else(|| {
        Input::new()
            .with_prompt("Project name")
            .default("my-farm-app".to_string())
            .interact_text()
            .expect("failed to read project name")
    });

    let template: String = match template {
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

    let pm: String = match pm {
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
    println!("  {} run dev", pm);
}

fn build_create_command(pm: &str, name: &str, template: &str) -> Command {
    let mut cmd = Command::new(pm);
    match pm {
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
