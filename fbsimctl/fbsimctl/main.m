/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@import FBSimulatorControlKit;

/**
 fbsimctl is a pure Objective-C Target.
 FBSimulatorControlKit is a Swift/Objective-C Target.
 The CLI Class is a Swift NSObject that bootsraps the entire CLI.
 As fbsimctl is a pure Objective-C Target, it doesn't need to statically link the 'swift_static' libs.
 */
int main(int argc, const char *argv[]) {
  @autoreleasepool
  {
    return [CLIBootstrapper bootstrap];
  }
}
