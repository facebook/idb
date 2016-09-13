/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Framebuffer.h"

#import "FBSimulator+Framebuffer.h"
#import "FBSimulator+Connection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorConnection.h"

@implementation FBSimulator (Framebuffer)

- (nullable FBFramebuffer *)framebufferWithError:(NSError **)error
{
  return [[self
    connectWithError:error]
    connectToFramebuffer:error];
}

@end
