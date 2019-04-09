#!/usr/bin/env bash
set -e

TAG="0.4.0-Xcode-10.2.0"
git tag -a "${TAG}" -m"${TAG}"
git push origin "${TAG}"
git branch "tag/${TAG}" "${TAG}"
git checkout "tag/${TAG}"

