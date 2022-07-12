#!/usr/bin/env bash

set -e

if [ -z "$1" ]; then
  echo "Pass kernel version to be built. E.g. v5.14.16"
  exit 1
fi

echo "=========================================================="
echo "Building docker image"
echo "=========================================================="

docker build --pull --tag focal-mainline-builder .

docker container rm -f focal_mainline_builder

docker run -ti \
  --name focal_mainline_builder \
  -e kver="$1" \
  -v focal_mainline_builder_source:/home/source \
  focal-mainline-builder:latest \
  --flavour=generic \
  --exclude=cloud-tools,udebs \
  --buildmeta=yes

rm -rf ./debs/v*
docker cp focal_mainline_builder:/home/debs/${1} ./debs/

docker container rm focal_mainline_builder
