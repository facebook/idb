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

BUILD_DIRECTORY=build

set -eu

function build_deps() {
  pushd fbsimctl
  carthage bootstrap
  popd
}

function framework() {
  NAME=FBSimulatorControl
  xctool \
      -project $NAME.xcodeproj \
      -scheme $NAME \
      -sdk macosx \
      -derivedDataPath $BUILD_DIRECTORY \
      $1
}

function fbsimctl() {
  SCHEME=$1
  xctool \
      -workspace fbsimctl/fbsimctl.xcworkspace \
      -scheme $SCHEME \
      -sdk macosx \
      -derivedDataPath $BUILD_DIRECTORY \
      $2
}

function cli() {
  fbsimctl fbsimctl $1
}

function cli_framework() {
  fbsimctl FBSimulatorControlKit $1
}

if [[ "$MODE" = "all" ]]; then
  framework test
  cli_framework test
  cli build
elif [[ "$MODE" = "framework" ]]; then
  framework test
elif [[ "$MODE" = "cli" ]]; then
  build_deps
  cli build
elif [[ "$MODE" = "cli_framework" ]]; then
  build_deps
  cli_framework test
else
  echo "Invalid mode $MODE"
  print_usage
  exit 1
fi

