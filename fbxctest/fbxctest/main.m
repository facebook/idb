/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBXCTestBootstrapper.h"

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    if (![FBXCTestBootstrapper.new bootstrap]) {
      return 2;
    }
  }
  return 0;
}
