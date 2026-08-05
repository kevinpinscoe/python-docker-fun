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
| `v4.0.0` | Current release (semver tag) |
| `sha-<digest>` | Every push (immutable, for pinning) |

Images are signed with Cosign keyless signing. To verify:

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/kevinpinscoe/python-docker-fun/.github/workflows/build.yaml@refs/.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/kevinpinscoe/python-docker-fun:latest
```

Replace `latest` with any tag (e.g. `v4.0.0`) to verify a specific release.

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

## Supply chain — verifying a published image

Every image pushed to `ghcr.io/kevinpinscoe/python-docker-fun` carries three
attestations bound to its digest: an **SPDX SBOM** (what is inside), **SLSA
provenance** (where and how it was built), and a **Cosign signature** (who published
it, and whether it has changed since).

```bash
IMG=ghcr.io/kevinpinscoe/python-docker-fun:latest

docker buildx imagetools inspect "$IMG" --format '{{ json .SBOM }}'
docker buildx imagetools inspect "$IMG" --format '{{ json .Provenance }}'

cosign verify "$IMG" \
  --certificate-identity-regexp='.*' \
  --certificate-oidc-issuer-regexp='.*'

grype "$IMG"
```

On tag builds the SPDX document is also attached to the GitHub release. That copy is
a convenience for reading the inventory without a registry client — **the registry
attestation is the source of truth**, and the two can drift.

### The CVE gate reports, it does not block — and this image is why

The release workflow scans the pushed digest with Grype at `severity-cutoff: high`,
uploads the result to the **Security** tab, and does **not** fail the build.

Measured 2026-08-04: this image carries **444 findings at or above high** (91
critical, 353 high) out of **1,949** total. That is not a backlog to work through —
it is what `FROM python:3.14` contains. The Dockerfile is a single stage that copies
one script into the full Debian-based Python image, so essentially every finding is
inherited, some of it dating to 2009.

**The honest fix is a smaller base image, not a stricter gate.** `python:3.14-slim`
or a distroless Python would remove most of this at a stroke. Until that happens,
turning on `fail-build: true` would only mean the repo can never publish.

When the base is addressed, flip `fail-build` to `true` in
`.github/workflows/build.yaml`. Do not raise `severity-cutoff` to make findings
disappear, and do not delete the step. A CVE that genuinely does not affect this
image is dispositioned with an OpenVEX statement at `.vex/openvex.json`, committed
and reviewable — there is none today because nothing is being blocked.

### What the SBOM does not tell you

An SBOM is an inventory, not a clean bill of health. For this image specifically:

- **Single stage, so the inventory is comparatively honest** — everything in the
  image is in the final stage, and there are no build-stage dependencies hidden from
  the scan. If this ever becomes multi-stage, the earlier stages need
  `BUILDKIT_SBOM_SCAN_STAGE=true` or their dependencies vanish from the attestation.
- **`python_loop_output.py` is `COPY`'d in** without package metadata and will not
  appear as a component.
- **Being listed is not being reachable.** Most of the 1,949 findings are in Debian
  packages this container never executes.
- **Generators disagree.** Two SBOMs of this image, from different tools, will not
  match line for line.

**Known gap:** this image is built for the runner's platform only (`linux/amd64`),
so unlike the multi-arch images in this fleet there is no arm64 variant to scan —
but equally, an arm64 consumer has nothing to pull.

**Rebuild trigger:** a digest's CVE posture is frozen at build time and only
degrades. Cut a new release when the base image updates.
