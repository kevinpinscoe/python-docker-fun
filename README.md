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

# NOTE: this will show three high findings that the gate does not. See below.
grype "$IMG"
```

On tag builds the SPDX document is also attached to the GitHub release. That copy is
a convenience for reading the inventory without a registry client — **the registry
attestation is the source of truth**, and the two can drift.

### Scanning this image yourself shows three findings the gate does not

**This is the one thing to know before scanning this image locally.** A plain
`grype "$IMG"` reports **three high-severity CVEs**. The release gate reports zero and
passes. Neither number is wrong, and the difference is not drift:

```bash
IMG=ghcr.io/kevinpinscoe/python-docker-fun:latest

grype "$IMG"                          # 3 high findings
grype "$IMG" --vex .vex/openvex.json  # 0 — what the gate actually sees
```

The three are dispositioned in an OpenVEX document at `.vex/openvex.json`, committed in
this repository and reviewable. The workflow passes it to Grype's `vex:` input; your
local run does not unless you say so. Run the second command from a checkout of this
repo to reproduce the gate exactly.

They are the only suppressions here, and each is temporary by construction — every
statement names the CPython release that supersedes it:

| CVE | Where | Why it does not affect this image |
|---|---|---|
| CVE-2026-11940 | `tarfile` | Never imported; the image reads no archives. |
| CVE-2026-11972 | `tarfile` | Same. |
| CVE-2026-15308 | `html.parser` | Never imported; the server emits HTML and parses none. |

This was not assumed from reading the source. It was measured inside the image:
importing exactly the application's import set (`os`, `signal`, `threading`,
`datetime`, `http.server`) loads 116 modules, and neither `tarfile` nor `html.parser`
is among them. `html.parser` was checked explicitly because `http.server` *does* import
`html` for `escape` and could plausibly have dragged the parser in — it does not.

All three are fixed only in CPython 3.15.0b4/3.15.0, an unreleased major version, so no
base-image change removes them. Every alternative was built and scanned rather than
guessed: Alpine's `apk python3` ships 3.14.5 with 5 blocking findings,
`distroless/python3` is CPython 3.11 on Debian 12 with 55, and `3.15.0rc1` still leaves
one while shipping a release candidate to a public registry. **When the base reaches
3.15 stable, delete `.vex/openvex.json`** — the gate then stands on a genuinely empty
baseline.

### The CVE gate blocks

The release workflow scans the pushed digest with Grype at `severity-cutoff: high`,
uploads the result to the **Security** tab, and **fails the build** on any unsuppressed
finding at or above high. One is enough — `fail-build: true` is not a count threshold.

Getting to a blockable baseline took two base-image changes, each measured:

| Base | Findings | High + Critical |
|---|---|---|
| `python:3.14` (until 2026-08-05) | 1,949 | 444 |
| `python:3.14-slim` (2026-08-06) | 177 | 30 |
| `python:3.14-alpine` (2026-08-07 →) | **12** | **3, all suppressed → 0** |

`python_loop_output.py` imports nothing outside the standard library, so the full Debian
image was contributing a compiler toolchain, dev headers and assorted libraries this
container never executes — and every CVE in them. Almost all of the reduction came from
deleting software that was never used, not from waiving anything.

Do not raise `severity-cutoff` to make findings disappear, and do not delete the scan
step. A CVE that genuinely does not affect this image is dispositioned with an OpenVEX
statement, committed and reviewable, and only with evidence that the vulnerable code is
unreachable.

### What the SBOM does not tell you

An SBOM is an inventory, not a clean bill of health. For this image specifically:

- **Single stage, so the inventory is comparatively honest** — everything in the
  image is in the final stage, and there are no build-stage dependencies hidden from
  the scan. If this ever becomes multi-stage, the earlier stages need
  `BUILDKIT_SBOM_SCAN_STAGE=true` or their dependencies vanish from the attestation.
- **`python_loop_output.py` is `COPY`'d in** without package metadata and will not
  appear as a component.
- **Being listed is not being reachable.** That is the entire basis of the three VEX
  statements above: the vulnerable code ships inside CPython's standard library and is
  never loaded by this application.
- **Generators disagree.** Two SBOMs of this image, from different tools, will not
  match line for line.

**Single-platform, by design.** This image is built for `linux/amd64` only, so unlike
the multi-arch images in this fleet there is no arm64 variant to scan — and equally, an
arm64 consumer has nothing to pull. The sibling repos (`pastebooks`, `eng-tools`) are
multi-arch and scan each platform's digest separately, because Grype resolves a manifest
list to the runner's own platform and would otherwise check only one. That distinction
does not arise here.

**Rebuild trigger:** a digest's CVE posture is frozen at build time and only
degrades. Cut a new release when the base image updates.
