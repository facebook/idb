#!/bin/sh

if [ -z $1 ]; then
  echo "usage: build.sh <subcommand>"
  echo "available subcommands:"
  echo "  ci"
  exit
fi

set -eu

MODE=$1

function framework() {
  NAME='FBSimulatorControl'
  xctool \
      -project $NAME.xcodeproj \
      -scheme $NAME \
      -sdk macosx \
      $1
}

function cli() {
  NAME='fbsimctl'
  xctool \
      -workspace $NAME/$NAME.xcworkspace \
      -scheme $NAME \
      -sdk macosx \
      $1
}

if [ "$MODE" = "ci" ]; then
  framework test
  cli build
fi

