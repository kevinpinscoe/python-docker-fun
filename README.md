# Python Docker Fun

A collection of scripts I use when debugging Kubernetes pods and sometimes local containers. Built on Python 3.13.

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
