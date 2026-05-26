# volamar

A local Kubernetes cluster setup with Knative Serving and automated HTTPS via cert-manager and DuckDNS.

## Local cluster

A single-node [k0s](https://k0sproject.io/) cluster managed by [Flux CD](https://fluxcd.io/), running Knative Serving with automatic HTTPS for `*.paulasvb.duckdns.org`.

### Stack

| Component | Purpose |
|---|---|
| k0s | Lightweight single-node Kubernetes |
| Flux CD | GitOps — syncs `clusters/local/` from this repo |
| Knative Serving + Kourier | Serverless workloads |
| cert-manager + DuckDNS webhook | Automatic Let's Encrypt TLS via DNS-01 |

### Bootstrap

```sh
just up                   # start k0s, write kubeconfig.yaml
just env-github-token     # write GITHUB_TOKEN to .env
just flux-bootstrap       # install Flux and point it at this repo
```

`just flux-bootstrap` is idempotent and safe to re-run.

### Common operations

```sh
just status               # cluster and node status
just flux-status          # all Flux kustomizations and sources
just flux-reconcile       # force an immediate sync
just down                 # stop and reset the cluster
```

## Repository layout

```
apps/
  hello-knative/    ← sample Knative Service deployed via Flux
clusters/
  local/            ← Flux-managed manifests for the local cluster
infrastructure/
  cert-manager/     ← cert-manager Helm release + DuckDNS ClusterIssuer
  knative/          ← Knative Serving CRDs, Kourier, domain config
  knative-tls/      ← net-certmanager integration for automatic TLS
```
