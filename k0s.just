# k0s cluster lifecycle commands.
# Registered as a module in the main justfile — run with: just k0s <command>
#
# These target an ISOLATED single-node cluster driven by k0s.yaml, using its
# own data dir and status socket so a globally installed/running k0s
# (which uses /var/lib/k0s) is left untouched.

k0s_config := "k0s.yaml"
data_dir   := "/var/lib/k0s-local"
sock       := "/run/k0s-local-status.sock"
# Written to the path the top-level justfile, Flux bootstrap, and the MCP
# server all expect, so `just bootstrap` works against this cluster.
kubeconfig := "/tmp/volmar.yaml"

# Show available commands
default:
    @just --list k0s

# Generate a default k0s config into {{k0s_config}} (only if missing)
config:
    @test -f {{k0s_config}} || k0s config create > {{k0s_config}}
    @echo "Using config: {{k0s_config}}"

# Validate {{k0s_config}} against the k0s schema
validate:
    @k0s config validate --config {{k0s_config}} && echo "{{k0s_config}} is valid"

# Start the isolated single-node cluster from {{k0s_config}} (FOREGROUND, Ctrl-C to stop).
# Get its kubeconfig from another terminal with: just k0s kubeconfig
up: config
    @echo "Starting isolated local k0s (data-dir={{data_dir}}) from {{k0s_config}}..."
    sudo k0s controller --single \
        --config {{k0s_config}} \
        --data-dir {{data_dir}} \
        --status-socket {{sock}}

# Write the cluster's kubeconfig to {{kubeconfig}} and verify connection
kubeconfig:
    @sudo k0s kubeconfig admin --data-dir {{data_dir}} | tee {{kubeconfig}} > /dev/null
    @KUBECONFIG={{kubeconfig}} kubectl get nodes

# Print export statement for KUBECONFIG — load with: eval $(just k0s kube-env)
kube-env:
    @sudo k0s kubeconfig admin --data-dir {{data_dir}} > {{kubeconfig}} 2>/dev/null
    @echo "export KUBECONFIG={{kubeconfig}}"

# Show cluster status
status:
    @sudo k0s status --status-socket {{sock}}
    @echo ""
    @KUBECONFIG={{kubeconfig}} kubectl get nodes 2>/dev/null || true

# Health check: k0s running, API reachable, node + kube-system pods Ready
health:
    @echo "==> k0s process..."
    @sudo k0s status --status-socket {{sock}} | grep -q "Running" && echo "  ok: k0s is running" || (echo "  FAIL: k0s is not running"; exit 1)
    @echo "==> API server / node..."
    @KUBECONFIG={{kubeconfig}} kubectl wait --for=condition=Ready node --all --timeout=60s
    @echo "==> kube-system pods..."
    @KUBECONFIG={{kubeconfig}} kubectl wait pod --all -n kube-system --for=condition=Ready --timeout=120s
    @echo "==> Cluster is healthy."

# Stop and wipe the isolated cluster
down:
    @sudo k0s stop --status-socket {{sock}} 2>/dev/null || true
    @sudo k0s reset --data-dir {{data_dir}} 2>/dev/null || true
    @rm -f {{kubeconfig}}
    @echo "Local cluster stopped and reset."

# Open a shell with KUBECONFIG set
shell:
    @KUBECONFIG={{kubeconfig}} $SHELL

# Apply a manifest (usage: just k0s apply <file>)
apply file:
    @KUBECONFIG={{kubeconfig}} kubectl apply -f {{file}}
