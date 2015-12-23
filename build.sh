#!/bin/sh

function print_usage() {
  echo "usage: build.sh <subcommand>"
  echo "available subcommands:"
  echo "all framework cli cli_framework"
  exit 1
}

if [[ -n $MODE ]]; then
  echo "using mode $MODE"
elif [[ -n $1 ]]; then
  echo "using mode $1"
  MODE=$1
else
  echo 'No argument or MODE provided'
  print_usage
  exit 1
fi

set -eu


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

function cli_framework() {
  NAME='fbsimctl'
  SCHEME='FBSimulatorControlKit'
  xctool \
      -workspace $NAME/$NAME.xcworkspace \
      -scheme $SCHEME \
      -sdk macosx \
      $1
}

if [[ "$MODE" = "all" ]]; then
  framework test
  cli_framework test
  cli build
elif [[ "$MODE" = "framework" ]]; then
  framework test
elif [[ "$MODE" = "cli" ]]; then
  cli build
elif [[ "$MODE" = "cli_framework" ]]; then
  cli_framework test
else
  echo "Invalid mode $MODE"
  print_usage
  exit 1
fi

