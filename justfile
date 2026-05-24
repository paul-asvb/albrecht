k0s_config  := "k0s.yaml"
kubeconfig  := "kubeconfig.yaml"
flux_owner  := "paul-asvb"
flux_repo   := "rust-js-test"
flux_branch := "main"
flux_path   := "clusters/local"

# Show available commands
default:
    @just --list

# Install k0s binary (if not present)
install-k0s:
    @if ! command -v k0s &>/dev/null; then \
        echo "Installing k0s..."; \
        curl -sSLf https://get.k0s.sh | sudo sh; \
    else \
        echo "k0s already installed: $(k0s version)"; \
    fi

# Start the k0s cluster (single-node controller+worker)
up: install-k0s
    @if sudo k0s status &>/dev/null 2>&1; then \
        echo "k0s is already running"; \
    else \
        echo "Starting k0s cluster..."; \
        sudo k0s install controller --single; \
        sudo k0s start; \
        echo "Waiting for k0s to be ready..."; \
        sudo k0s kubectl wait --for=condition=Ready node --all --timeout=120s; \
        echo "Cluster is ready."; \
    fi
    @just kubeconfig

# Export kubeconfig for kubectl
kubeconfig:
    @sudo k0s kubeconfig admin | tee {{kubeconfig}} > /dev/null
    @echo "Kubeconfig written to {{kubeconfig}}"
    @echo "Run: export KUBECONFIG=$(pwd)/{{kubeconfig}}"

# Show cluster status
status:
    @sudo k0s status
    @echo ""
    @KUBECONFIG={{kubeconfig}} kubectl get nodes 2>/dev/null || true

# Stop the k0s cluster
down:
    @echo "Stopping k0s cluster..."
    @sudo k0s stop
    @sudo k0s reset
    @rm -f {{kubeconfig}}
    @echo "Cluster stopped and reset."

# Restart the cluster
restart: down up

# Open a shell with KUBECONFIG set
shell:
    @KUBECONFIG=$(pwd)/{{kubeconfig}} $SHELL

# Apply a manifest (usage: just apply <file>)
apply file:
    @KUBECONFIG={{kubeconfig}} kubectl apply -f {{file}}

# Write GITHUB_TOKEN from gh CLI into .env
env-github-token:
    @gh auth token | xargs -I{} sh -c 'grep -q "^GITHUB_TOKEN=" .env 2>/dev/null && sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN={}/" .env || echo "GITHUB_TOKEN={}" >> .env'
    @echo "GITHUB_TOKEN written to .env"

# ── Flux ────────────────────────────────────────────────────────────────────

# Install flux CLI (if not present)
install-flux:
    @if ! command -v flux &>/dev/null; then \
        echo "Installing flux CLI..."; \
        curl -s https://fluxcd.io/install.sh | sudo bash; \
    else \
        echo "flux already installed: $(flux version --client 2>/dev/null | head -1)"; \
    fi

# Bootstrap Flux into the cluster from GitHub (idempotent)
flux-bootstrap: install-flux
    @export $(grep -v '^#' .env | xargs) 2>/dev/null; \
    test -n "${GITHUB_TOKEN:-}" || (echo "Error: GITHUB_TOKEN is not set (run: just env-github-token)"; exit 1)
    @export $(grep -v '^#' .env | xargs) 2>/dev/null; \
    KUBECONFIG=$(pwd)/{{kubeconfig}} flux bootstrap github \
        --owner={{flux_owner}} \
        --repository={{flux_repo}} \
        --branch={{flux_branch}} \
        --path={{flux_path}} \
        --personal \
        --token-auth

# Check Flux component and reconciliation status
flux-status:
    @KUBECONFIG=$(pwd)/{{kubeconfig}} flux get all --all-namespaces

# Force an immediate reconciliation cycle
flux-reconcile:
    @KUBECONFIG=$(pwd)/{{kubeconfig}} flux reconcile source git flux-system
    @KUBECONFIG=$(pwd)/{{kubeconfig}} flux reconcile kustomization flux-system

# Tear down Flux controllers (leaves cluster running, removes flux-system namespace)
flux-uninstall:
    @KUBECONFIG=$(pwd)/{{kubeconfig}} flux uninstall --silent
