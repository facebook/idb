/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorEraseStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorShutdownStrategy.h"

@implementation FBSimulatorEraseStrategy

#pragma mark Public

+ (FBFuture<NSNull *> *)erase:(FBSimulator *)simulator
{
  return [[FBSimulatorShutdownStrategy
    shutdown:simulator]
    onQueue:simulator.workQueue fmap:^(id _) {
      return [self eraseContentsAndSettings:simulator];
    }];
}

#pragma mark Private

+ (FBFuture<FBSimulator *> *)eraseContentsAndSettings:(FBSimulator *)simulator
{
  [simulator.logger logFormat:@"Erasing %@", simulator];
  FBMutableFuture<FBSimulator *> *future = FBMutableFuture.future;
  [simulator.device
    eraseContentsAndSettingsAsyncWithCompletionQueue:simulator.workQueue
    completionHandler:^(NSError *error){
      if (error) {
        [future resolveWithError:error];
      } else {
        [simulator.logger logFormat:@"Erased %@", simulator];
        [future resolveWithResult:simulator];
      }
    }];
  return future;
}

@end
