# Isolated local k0s cluster lifecycle (k0s.just) — run as: just k0s <command>
mod k0s

k0s_config  := "k0s.yaml"
kubeconfig  := "/tmp/volmar.yaml"

# Isolated local cluster: its own data dir + status socket so it never
# touches a globally installed/running k0s (which uses /var/lib/k0s).
local_data_dir   := "/var/lib/k0s-local"
local_sock       := "/run/k0s-local-status.sock"
local_kubeconfig := "/tmp/albrecht-local.yaml"
flux_owner  := "paul-asvb"
flux_repo   := "albrecht"
flux_branch := "main"
flux_path   := "clusters/local"

# Show available commands
default:
    @just --list

# Start the k0s cluster (single-node controller+worker)
connect:
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


# Generate a default k0s config into {{k0s_config}} (only if missing)
local-config:
    @test -f {{k0s_config}} || k0s config create > {{k0s_config}}
    @echo "Using config: {{k0s_config}}"

# Start an isolated single-node local k0s cluster from {{k0s_config}}.
# Runs in the FOREGROUND (Ctrl-C to stop). It uses its own data dir and
# status socket, so a globally installed/running k0s is left untouched.
# Get its kubeconfig from another terminal with: just local-kubeconfig
local-up: local-config
    @echo "Starting isolated local k0s (data-dir={{local_data_dir}}) from {{k0s_config}}..."
    sudo k0s controller --single \
        --config {{k0s_config}} \
        --data-dir {{local_data_dir}} \
        --status-socket {{local_sock}}

# Write the isolated local cluster's kubeconfig and verify connection
local-kubeconfig:
    @sudo k0s kubeconfig admin --data-dir {{local_data_dir}} | tee {{local_kubeconfig}} > /dev/null
    @KUBECONFIG={{local_kubeconfig}} kubectl get nodes

# Stop and wipe the isolated local cluster (does not affect global k0s)
local-down:
    @sudo k0s stop --status-socket {{local_sock}} 2>/dev/null || true
    @sudo k0s reset --data-dir {{local_data_dir}} 2>/dev/null || true
    @rm -f {{local_kubeconfig}}
    @echo "Local cluster stopped and reset."

# Write k0s kubeconfig to /tmp/volmar.yaml and verify cluster connection
kubeconfig:
    @sudo k0s kubeconfig admin | tee /tmp/volmar.yaml > /dev/null
    @KUBECONFIG=/tmp/volmar.yaml kubectl get nodes

# Print export statement for KUBECONFIG — load into shell with: eval $(just kube-env)
kube-env:
    @sudo k0s kubeconfig admin > /tmp/volmar.yaml 2>/dev/null
    @echo "export KUBECONFIG=/tmp/volmar.yaml"

# Show cluster status
status:
    @sudo k0s status
    @echo ""
    @KUBECONFIG={{kubeconfig}} kubectl get nodes 2>/dev/null || true

# Start the k0s service (installs service unit if needed)
start:
    @sudo k0s install controller --single 2>/dev/null || true
    @sudo k0s start

# Stop the k0s service (keeps cluster state)
stop:
    @if sudo k0s status &>/dev/null; then sudo k0s stop; else echo "k0s is not running"; fi

# Stop the k0s cluster
down:
    @echo "Stopping k0s cluster..."
    @if sudo k0s status &>/dev/null; then sudo k0s stop; fi
    @sudo k0s reset
    @rm -f {{kubeconfig}}
    @echo "Cluster stopped and reset."


# Open a shell with KUBECONFIG set
shell:
    @KUBECONFIG={{kubeconfig}} $SHELL

# Apply a manifest (usage: just apply <file>)
apply file:
    @KUBECONFIG={{kubeconfig}} kubectl apply -f {{file}}

# Re-run after cert-manager rotates the CA (~every 90 days).
# Trust the cluster CA system-wide + in browsers (removes HTTPS warnings).
trust-ca:
    @KUBECONFIG={{kubeconfig}} ./scripts/trust-ca.sh

# Write GITHUB_TOKEN from gh CLI into .env
env-github-token:
    @gh auth token | xargs -I{} sh -c 'grep -q "^GITHUB_TOKEN=" .env 2>/dev/null && sed -i "s/^GITHUB_TOKEN=.*/GITHUB_TOKEN={}/" .env || echo "GITHUB_TOKEN={}" >> .env'
    @echo "GITHUB_TOKEN written to .env"

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
    KUBECONFIG={{kubeconfig}} flux bootstrap github \
        --owner={{flux_owner}} \
        --repository={{flux_repo}} \
        --branch={{flux_branch}} \
        --path={{flux_path}} \
        --personal \
        --token-auth

# Check Flux component and reconciliation status
flux-status:
    @KUBECONFIG={{kubeconfig}} flux get all --all-namespaces

# Force an immediate reconciliation cycle
flux-reconcile:
    @KUBECONFIG={{kubeconfig}} flux reconcile source git flux-system
    @KUBECONFIG={{kubeconfig}} flux reconcile kustomization flux-system

# Tear down Flux controllers (leaves cluster running, removes flux-system namespace)
flux-uninstall:
    @KUBECONFIG={{kubeconfig}} flux uninstall --silent

# Wait until k0s is running and all kube-system pods are Ready
wait-healthy:
    @echo "Waiting for k0s to report Running..."
    @until sudo k0s status 2>/dev/null | grep -q "Running"; do sleep 2; done
    @echo "k0s is running."
    @echo "Waiting for k0s API server (kubeconfig) to be ready..."
    @until sudo k0s kubeconfig admin > {{kubeconfig}} 2>/dev/null; do sleep 2; done
    @echo "API server is up."
    @echo "Waiting for kube-system pods to be ready..."
    @KUBECONFIG={{kubeconfig}} kubectl wait pod \
        --all --namespace kube-system \
        --for=condition=Ready \
        --timeout=300s
    @echo "Cluster is healthy."

# Destroy the k0s cluster and re-run Flux bootstrap from scratch
reset:
    @sudo -n true 2>/dev/null || (echo "Error: passwordless sudo required — run 'sudo -v' first"; exit 1)
    @just down start wait-healthy flux-bootstrap

# Set up the hello-knative demo from zero: cluster → Flux → wait for ready
# Prerequisites: gh CLI authenticated
bootstrap: env-github-token
    @echo "==> Bootstrapping Flux..."
    @just flux-bootstrap
    @echo "==> Triggering reconciliation..."
    @KUBECONFIG={{kubeconfig}} flux reconcile kustomization flux-system --with-source
    @echo "==> Waiting for cert-manager (up to 5 min)..."
    @KUBECONFIG={{kubeconfig}} kubectl wait -n flux-system \
        kustomization/cert-manager \
        --for=condition=Ready --timeout=300s
    @echo "==> Waiting for knative-serving and knative-tls (up to 10 min)..."
    @KUBECONFIG={{kubeconfig}} kubectl wait -n flux-system \
        kustomization/knative-serving \
        kustomization/knative-tls \
        --for=condition=Ready --timeout=600s
    @echo ""
    @echo "Done. Services will be available at https://<name>.default.192.168.1.249.sslip.io"
