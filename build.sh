#!/bin/sh

if [ -z $1 ]; then
  echo "usage: build.sh <subcommand>"
  echo "available subcommands:"
  echo "  ci"
  exit
fi

set -eu

MODE=$1

function ci() {
  pod install
  xctool \
      -workspace $1.xcworkspace \
      -scheme $1 \
      -sdk macosx \
      $2
}

if [ "$MODE" = "ci" ]; then
  ci FBSimulatorControl test
fi

