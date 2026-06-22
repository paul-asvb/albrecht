# albrecht

A local Kubernetes cluster setup with Knative Serving, automatic TLS via
cert-manager (self-signed CA), and Crossplane-managed customer namespaces.

## Local cluster

```bash
eval $(just kube-env)
```

A single-node [k0s](https://k0sproject.io/) cluster managed by
[Flux CD](https://fluxcd.io/), running Knative Serving with automatic HTTPS for
`*.<node-ip>.sslip.io` hostnames.

### Stack

| Component | Purpose |
|---|---|
| k0s | Lightweight single-node Kubernetes |
| Flux CD | GitOps — syncs `clusters/local/` from this repo |
| Knative Serving + Kourier | Serverless workloads |
| cert-manager | Issues TLS certs from an in-cluster self-signed CA |
| Crossplane + provider-kubernetes | Composition-based provisioning (e.g. `CustomerNamespace`) |

### Prerequisites

Install the following tools before bootstrapping:

| Tool | Install |
|---|---|
| [k0s](https://k0sproject.io/) | `curl -sSLf https://get.k0s.sh \| sudo sh` |
| [just](https://github.com/casey/just) | `cargo install just` (or your package manager) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | see upstream docs |
| [flux](https://fluxcd.io/flux/installation/) | `curl -s https://fluxcd.io/install.sh \| sudo bash` |
| [gh](https://cli.github.com/) | GitHub CLI, authenticated (`gh auth login`) |

### Bootstrap

```sh
just connect              # start k0s, write kubeconfig to /tmp/volmar.yaml
just env-github-token     # write GITHUB_TOKEN to .env (uses gh CLI)
just bootstrap            # install Flux, reconcile, wait for cert-manager + Knative
```

`just bootstrap` is idempotent and safe to re-run. It runs `flux-bootstrap`,
forces a reconciliation, then waits for the core kustomizations to become
ready.

### Common operations

```sh
just status               # cluster and node status
just flux-status          # all Flux kustomizations and sources
just flux-reconcile       # force an immediate sync
just kube-env             # prints `export KUBECONFIG=…` — eval to load
just down                 # stop and reset the cluster
```

Services deployed via Knative will be reachable at
`https://<name>.<namespace>.<node-ip>.sslip.io`.

## Repository layout

```
apps/
  hello-knative/                 ← sample Knative Service
  customer-namespace-example/    ← example Crossplane claim (do not apply directly)
clusters/
  local/                         ← Flux-managed manifests for the local cluster
infrastructure/
  cert-manager/                  ← cert-manager Helm release
  cert-manager-config/           ← self-signed CA + ClusterIssuers
  knative/                       ← Knative Serving CRDs, Kourier, domain config
  knative-tls/                   ← net-certmanager integration for automatic TLS
  crossplane/                    ← Crossplane Helm release
  crossplane-providers/          ← provider-kubernetes + RBAC
  crossplane-config/             ← XRD, Composition, ProviderConfig
```

## Customer namespaces

Crossplane exposes a `CustomerNamespace` claim that provisions a namespace per
customer:

```yaml
apiVersion: volamar.io/v1alpha1
kind: CustomerNamespace
metadata:
  name: acme
  namespace: default
spec:
  customer: acme
```

See `apps/customer-namespace-example/claim.yaml` for the template.
