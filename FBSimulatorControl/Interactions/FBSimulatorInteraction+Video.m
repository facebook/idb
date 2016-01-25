/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Video.h"

#import "FBInteraction+Private.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLogs.h"
#import "FBSimulatorVideoRecorder.h"
#import "FBSimulatorWindowTiler.h"
#import "FBSimulatorWindowTilingStrategy.h"
#import "FBWritableLog.h"

@implementation FBSimulatorInteraction (Video)

- (instancetype)tileSimulator:(id<FBSimulatorWindowTilingStrategy>)tilingStrategy
{
  NSParameterAssert(tilingStrategy);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBSimulatorWindowTiler *tiler = [FBSimulatorWindowTiler withSimulator:simulator strategy:tilingStrategy];
    NSError *innerError = nil;
    if (CGRectIsNull([tiler placeInForegroundWithError:&innerError])) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)tileSimulator
{
  return [self tileSimulator:[FBSimulatorWindowTilingStrategy horizontalOcclusionStrategy:self.simulator]];
}

- (instancetype)recordVideo
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBWritableLogBuilder *logBuilder = [[self.simulator.logs.logBuilder
      updateShortName:FBSimulatorLogNameVideo]
      updateFileType:@"mp4"];

    NSString *path = [logBuilder createPath];

    FBSimulatorVideoRecorder *recorder = [FBSimulatorVideoRecorder forSimulator:simulator logger:nil];
    NSError *innerError = nil;
    if (![recorder startRecordingToFilePath:path error:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to start recording video"] inSimulator:simulator] failBool:error];
    }

    [simulator.eventSink logAvailable:[[logBuilder updatePath:path] build]];
    [simulator.eventSink terminationHandleAvailable:recorder];

    return YES;
  }];
}

@end
