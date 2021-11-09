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

if [ ! -d ./src/cod ]; then
  echo "=========================================================="
  echo "Getting kernel tree"
  echo "=========================================================="

  git clone \
    git://git.launchpad.net/~ubuntu-kernel-test/ubuntu/+source/linux/+git/mainline-crack \
    ./src/cod
else
  echo "=========================================================="
  echo "Got kernel sources already"
  echo "=========================================================="
fi

docker run -ti --rm \
  -e kver="$1" \
  -v "${PWD}/src/cod":/home/source \
  -v "${PWD}/debs":/home/debs \
  focal-mainline-builder:latest \
  --exclude=cloud-tools,udebs \
  --buildmeta=yes

