/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridgeCommands.h"

#import <FBControlCore/FBControlCore.h>

#import "FBFramebuffer.h"
#import "FBSimulator.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"
#import "FBSimulatorVideoRecordingCommands.h"

@interface FBSimulatorBridgeCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorBridgeCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

- (BOOL)tap:(double)x y:(double)y error:(NSError **)error
{
  FBSimulatorBridge *bridge = [[self.simulator connectWithError:error] connectToBridge:error];
  if (!bridge) {
    return NO;
  }
  return [bridge tapX:x y:y error:error];
}

- (BOOL)setLocation:(double)latitude longitude:(double)longitude error:(NSError **)error
{
  FBSimulatorBridge *bridge = [[self.simulator connectWithError:error] connectToBridge:error];
  if (!bridge) {
    return NO;
  }
  [bridge setLocationWithLatitude:latitude longitude:longitude];
  return YES;
}

@end
