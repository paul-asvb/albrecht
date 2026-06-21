# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

`albrecht` is a **GitOps-managed local Kubernetes platform**. A single-node
[k0s](https://k0sproject.io/) cluster is reconciled by [Flux CD](https://fluxcd.io/)
from this Git repo. It runs Knative Serving (serverless workloads) with automatic
TLS via cert-manager (self-signed CA), Crossplane for composition-based
provisioning, and Zitadel + oauth2-proxy for authentication.

This is primarily a **declarative manifest repo** — most changes are YAML, not
code. The only application code is the `plattform` Rust service.

## Repository layout

```
apps/                    Application workloads (Knative Services, Crossplane claims)
  hello-knative/         Sample Knative Service
  plattform/             Rust (axum) service — the only compiled code here
clusters/local/          Flux entrypoint for the local cluster (see kustomization.yaml)
  flux-system/           Flux controllers + sync config (managed by `flux bootstrap`)
  infrastructure/        Flux Kustomizations pointing into infrastructure/
  apps/                  Flux Kustomizations pointing into apps/
infrastructure/          Helm releases + manifests for platform components
  cert-manager*/ knative*/ crossplane*/ zitadel*/ registry/ ...
justfile                 All cluster lifecycle commands
.mcp.json                Kubernetes MCP server (uses KUBECONFIG=/tmp/volmar.yaml)
```

Flux reconciles `clusters/local/`, which aggregates `infrastructure/` and `apps/`.
**Pushing to `main` is the deploy mechanism** — Flux pulls and applies.

## Key facts for agents

- **`kubectl`/`flux` need a kubeconfig.** It lives at `/tmp/volmar.yaml`. Load it
  with `eval $(just kube-env)` or prefix commands with `KUBECONFIG=/tmp/volmar.yaml`.
  The MCP `kubernetes` server is already configured to use this path.
- **The cluster is GitOps-driven.** Don't `kubectl apply` permanent changes — they
  get reverted on the next Flux reconcile. Edit the manifests and let Flux apply
  them (`just flux-reconcile` to force a sync). `just apply <file>` exists for
  one-off/debugging only.
- **Most operations are in the `justfile`** — read it first. Run `just` (or
  `just --list`) to see commands.
- **Service URLs** follow `https://<name>.<namespace>.<node-ip>.sslip.io`
  (node IP is currently `192.168.1.249`).
- Several commands require **passwordless sudo** (k0s lifecycle).

## Common commands

```sh
eval $(just kube-env)     # load KUBECONFIG into the shell
just connect              # start k0s, write kubeconfig
just bootstrap            # install Flux + reconcile + wait for core components
just status               # cluster/node status
just flux-status          # all Flux kustomizations and sources
just flux-reconcile       # force an immediate sync (after pushing manifest changes)
just down                 # stop and reset the cluster
```

## The `plattform` Rust service

- Location: `apps/plattform/`. Stack: axum 0.8 + tokio, routes `/` and `/health`,
  listens on `$PORT` (default 8080).
- Build/test locally: `cd apps/plattform && cargo build && cargo test`.
- CI (`.github/workflows/plattform.yaml`) builds and pushes the image to
  `ghcr.io/<repo>` on pushes to `main` that touch `apps/plattform/**`.
- Deployed as a Knative Service (`apps/plattform/ksvc.yaml`) behind oauth2-proxy.

> Note: the Dockerfile copies a binary named `walter`, while the Cargo package is
> `plattform`. If you touch the build, verify the binary name matches before
> assuming it works.

## Conventions

- Every manifest directory has a `kustomization.yaml`. When adding a manifest,
  add it to the relevant `kustomization.yaml` or Flux won't pick it up.
- Keep changes declarative and let Flux reconcile; verify with `just flux-status`.
- Match the structure and naming of existing manifests in the same component
  directory.
