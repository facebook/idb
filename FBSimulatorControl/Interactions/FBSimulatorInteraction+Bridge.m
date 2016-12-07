/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Bridge.h"

#import <FBControlCore/FBControlCore.h>

#import "FBFramebuffer.h"
#import "FBSimulator.h"
#import "FBSimulator+Connection.h"
#import "FBSimulator+Framebuffer.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorVideoRecordingCommands.h"

@implementation FBSimulatorInteraction (Bridge)

- (instancetype)startRecordingVideo
{
  id<FBVideoRecordingCommands> commands = [FBSimulatorVideoRecordingCommands withSimulator:self.simulator];
  return [self chainNext:[FBCommandInteractions startRecordingWithCommand:commands]];
}

- (instancetype)stopRecordingVideo
{
  id<FBVideoRecordingCommands> commands = [FBSimulatorVideoRecordingCommands withSimulator:self.simulator];
  return [self chainNext:[FBCommandInteractions stopRecordingWithCommand:commands]];
}

- (instancetype)tap:(double)x y:(double)y
{
  return [self interactWithBridge:^ BOOL (NSError **error, FBSimulator *simulator, FBSimulatorBridge *bridge) {
    return [bridge tapX:x y:y error:error];
  }];
}

- (instancetype)setLocation:(double)latitude longitude:(double)longitude
{
  return [self interactWithBridge:^ BOOL (NSError **error, FBSimulator *simulator, FBSimulatorBridge *bridge) {
    [bridge setLocationWithLatitude:latitude longitude:longitude];
    return YES;
  }];
}

#pragma mark Private

- (instancetype)interactWithBridge:(BOOL (^)(NSError **error, FBSimulator *simulator, FBSimulatorBridge *bridge))block
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    FBSimulatorBridge *bridge = [[simulator connectWithError:&innerError] connectToBridge:&innerError];
    if (!bridge) {
      return [[[[FBSimulatorError
        describe:@"Could not connect to Simulator Connection"]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }
    return block(error, simulator, bridge);
  }];
}

@end
