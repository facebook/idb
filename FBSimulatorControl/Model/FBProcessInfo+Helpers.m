/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessInfo+Helpers.h"

#import "FBSimulatorApplication.h"

@implementation FBProcessInfo (Helpers)

- (FBSimulatorBinary *)binary
{
  return [FBSimulatorBinary binaryWithPath:self.launchPath error:nil];
}

@end
