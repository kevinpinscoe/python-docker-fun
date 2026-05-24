#!/bin/bash -v

# Local build script for python-docker-fun — kept for reference.
# CI (build.yaml) handles builds and pushes automatically on main and version tags.

image="ghcr.io/kevinpinscoe/python-docker-fun"
version="${1:-latest}"

docker build -t "${image}:${version}" -f Dockerfile .
echo "Image ID: $(docker images -q "${image}:${version}")"
gh auth token | docker login ghcr.io -u kevinpinscoe --password-stdin
docker push "${image}:${version}"
