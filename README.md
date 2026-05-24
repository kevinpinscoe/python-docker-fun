# Python Docker Fun

A collection of scripts I use when debugging Kubernetes pods and sometimes local containers. Built on Python 3.13.

Originally written as a simple debugging loop, this repo has since been modernized with a current CI/CD workflow, GHCR publishing, Cosign image signing, updated manifests, and an improved Python script with graceful shutdown, pod metadata logging, and an HTTP health endpoint.

## Running from GHCR

The image is published to GitHub Container Registry automatically. Build triggers:

| Event | Tags published |
|---|---|
| Push to `main` | `main`, `latest`, `sha-<digest>` |
| Push of `v*.*.*` tag | `v1.2.3`, `latest`, `sha-<digest>` |
| Pull request to `main` | build only — no image pushed |


```bash
docker pull ghcr.io/kevinpinscoe/python-docker-fun:latest
docker run --rm ghcr.io/kevinpinscoe/python-docker-fun:latest
```

Available tags:

| Tag | When it updates |
|---|---|
| `latest` | Every version tag push |
| `main` | Every push to the `main` branch |
| `v1.2.3` | Exact version tag (semver) |
| `sha-<digest>` | Every push (immutable, for pinning) |

Images are signed with Cosign keyless signing. To verify:

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/kevinpinscoe/python-docker-fun/.github/workflows/build.yaml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/kevinpinscoe/python-docker-fun:latest
```

## Features

- **Timestamped loop** — prints version, iteration counter, and UTC timestamp every 60 seconds
- **Pod metadata** — logs `POD_NAME`, `POD_NAMESPACE`, and `NODE_NAME` on startup and in each line (injected via the k8s downward API)
- **HTTP health endpoint** — listens on `:8080/health`, returns `200 ok`; wired to liveness and readiness probes in the k8s manifests
- **Graceful shutdown** — catches `SIGTERM` and `SIGINT`, exits cleanly without waiting for the next 60-second tick

To hit the health endpoint locally:

```bash
docker run --rm -p 8080:8080 ghcr.io/kevinpinscoe/python-docker-fun:latest
curl http://localhost:8080/health
```

## Repository Layout

```
python-docker-fun/
├── .github/
│   ├── dependabot.yml                     # automated dependency updates
│   └── workflows/
│       └── build.yaml                     # build, push, and sign to GHCR
├── Dockerfile                             # Python 3.13 container image
├── python_loop_output.py                  # main loop script
├── python_loop_output_deployment.yaml     # k8s Pod manifest (loop container)
├── python_loop_output_load_test.yaml      # k8s load test manifest
├── nginx.yaml                             # k8s nginx Deployment (150 replicas)
├── build_python_loop_output.sh            # local build/push script (reference)
├── .gitignore
└── README.md
```

## Kubernetes

To apply the loop to a k8s cluster:

```bash
kubectl apply -f python_loop_output_deployment.yaml
```

An nginx deployment (`nginx:1.30.2`) is also included for load-testing alongside the loop. It runs 150 replicas and exposes port 80:

```bash
kubectl apply -f nginx.yaml
```

To run a higher-replica load test of the loop container (111 replicas):

```bash
kubectl apply -f python_loop_output_load_test.yaml
```
