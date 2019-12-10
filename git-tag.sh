#!/usr/bin/env bash
set -e

TAG="0.4.0-Xcode-11.2.1"
git tag -a "${TAG}" -m"${TAG}"
git push origin "${TAG}"
git branch "tag/${TAG}" "${TAG}"
git checkout "tag/${TAG}"

