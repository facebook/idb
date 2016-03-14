/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
    return [CLI bootstrap];
  }
}
