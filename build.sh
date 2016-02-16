# vim: set tabstop=2 shiftwidth=2 filetype=sh:
#!/bin/sh

set -e

BUILD_DIRECTORY=build

function build_deps() {
  pushd fbsimctl
  carthage bootstrap --platform Mac
  popd
}

function framework_build() {
  NAME=FBSimulatorControl
  xcodebuild \
    -project $NAME.xcodeproj \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build

  if [[ -n $OUTPUT_DIRECTORY ]]; then
    ARTIFACT="$BUILD_DIRECTORY/Build/Products/Debug/FBSimulatorControl.framework"
    echo "Copying Build output from $ARTIFACT to $OUTPUT_DIRECTORY"
    mkdir -p $OUTPUT_DIRECTORY
    cp -r $ARTIFACT $OUTPUT_DIRECTORY
  fi
}

function framework_test() {
  NAME=FBSimulatorControl
  xctool \
    -project $NAME.xcodeproj \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function cli_build() {
  NAME=fbsimctl
  xcodebuild \
    -workspace $NAME/$NAME.xcworkspace \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build
  
  if [[ -n $OUTPUT_DIRECTORY ]]; then
    ARTIFACT="$BUILD_DIRECTORY/Build/Products/Debug/*"
    echo "Copying Build output from $ARTIFACT to $OUTPUT_DIRECTORY"
    mkdir -p $OUTPUT_DIRECTORY
    cp -r $ARTIFACT $OUTPUT_DIRECTORY
  fi
}

function cli_test() {
  NAME=fbsimctl
  xctool \
    -workspace $NAME/$NAME.xcworkspace \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function print_usage() {
cat <<EOF
./build.sh usage:
  /build.sh <target> <command> [<arg>]*

Supported Commands:
  help
    Print usage.
  framework build <output-directory>
    Build the FBSimulatorControl.framework. Optionally copies the Framework to <output-directory>
  framework test
    Build then Test the FBSimulatorControl.framework. Requires xctool to be installed.
  cli build <output-directory>
    Build the fbsimctl exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  cli test
    Build the FBSimulatorControlKit.framework and runs the tests. Requires xctool to be installed.
EOF
}

if [[ -n $TARGET ]]; then
  echo "using target $TARGET"
elif [[ -n $1 ]]; then
  TARGET=$1
  echo "using target $TARGET"
else
  echo "No target argument or $TARGET provided"
  print_usage
  exit 1
fi

if [[ -n $COMMAND ]]; then
  echo "using command $COMMAND"
elif [[ -n $2 ]]; then
  COMMAND=$2
  echo "using command $COMMAND"
else 
  echo "No command argument or $COMMAND provided"
  print_usage
  exit 1
fi

if [[ -n $OUTPUT_DIRECTORY ]]; then
  echo "using output directory $OUTPUT_DIRECTORY"
elif [[ -n $3 ]]; then
  echo "using output directory $3"
  OUTPUT_DIRECTORY=$3
fi

case $TARGET in
  help) 
    print_usage;;
  framework)
    case $COMMAND in
      build) 
        framework_build;;
      test) 
        framework_test;;
      *) 
        echo "Unknown Command $2"
        exit 1;;
    esac;;
  cli)
    build_deps
    case $COMMAND in
      build) 
        cli_build;;
      test)
        cli_test;;
      *)
        echo "Unknown Command $COMMAND"
        exit 1;;
    esac;;
  *) 
    echo "Unknown Command $TARGET"
    exit 1;;
esac

