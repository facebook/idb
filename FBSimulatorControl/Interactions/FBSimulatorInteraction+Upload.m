/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Upload.h"

#import <CoreSimulator/SimDevice.h>

#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Applications.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@implementation FBSimulatorInteraction (Upload)

- (instancetype)uploadPhotos:(NSArray *)photoPaths
{
  if (!photoPaths.count) {
    return [self succeed];
  }

  return [self interactWithBootedSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    if (simulator.state != FBSimulatorStateBooted) {
      return [[FBSimulatorError describeFormat:@"Simulator must be booted to upload photos, is %@", simulator.device.stateString] failBool:error];
    }

    for (NSString *path in photoPaths) {
      NSURL *url = [NSURL fileURLWithPath:path];

      NSError *innerError = nil;
      if (![simulator.device addPhoto:url error:&innerError]) {
        return [[[FBSimulatorError describeFormat:@"Failed to upload photo at path %@", path] causedBy:innerError] failBool:error];
      }
    }
    return YES;
  }];
}

- (instancetype)uploadVideos:(NSArray *)videoPaths
{
  if (!videoPaths.count) {
    return [self succeed];
  }

  return [self interactWithBootedSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    BOOL success = [simulator.simDeviceWrapper addVideos:videoPaths error:&innerError];
    if (!success) {
      return [[[FBSimulatorError describeFormat:@"Failed to upload videos at paths %@", videoPaths]
        causedBy:innerError]
        failBool:error];
    }

    return YES;
  }];
}

@end
