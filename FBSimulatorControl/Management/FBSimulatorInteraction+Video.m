/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Video.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBInteraction+Private.h"

#import "FBSimulatorError.h"
#import "FBSimulatorWindowTiler.h"
#import "FBSimulatorVideoRecorder.h"
#import "FBSimulatorWindowTilingStrategy.h"
#import "FBSimulatorSessionLifecycle.h"

@implementation FBSimulatorInteraction (Video)

- (instancetype)tileSimulator:(id<FBSimulatorWindowTilingStrategy>)tilingStrategy
{
  NSParameterAssert(tilingStrategy);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
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
  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self interact:^ BOOL (NSError **error, id _) {
    FBSimulatorVideoRecorder *recorder = [FBSimulatorVideoRecorder forSimulator:simulator logger:nil];
    NSString *path = [lifecycle pathForStorage:@"video" ofExtension:@"mp4"];

    NSError *innerError = nil;
    if (![recorder startRecordingToFilePath:path error:&innerError]) {
      return [[[FBSimulatorError describe:@"Failed to start recording video"] inSimulator:simulator] failBool:error];
    }

    [lifecycle associateEndOfSessionCleanup:recorder];
    [lifecycle sessionDidGainDiagnosticInformationWithName:@"video" data:path];
    return YES;
  }];
}

@end
