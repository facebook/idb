/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "ServiceDispatch.h"

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithCapacity:argc];
    for (int i = 0; i < argc; i++) {
      [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    return runBridgeCommand(arguments);
  }
}
