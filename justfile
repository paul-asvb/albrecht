k0s_config := "k0s.yaml"
kubeconfig := "kubeconfig.yaml"

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
