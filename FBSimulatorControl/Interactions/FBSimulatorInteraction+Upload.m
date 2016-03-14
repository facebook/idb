/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Upload.h"

#import <Cocoa/Cocoa.h>

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

@implementation FBSimulatorInteraction (Upload)

- (instancetype)uploadMedia:(NSArray<NSString *> *)mediaPaths
{
  if (!mediaPaths.count) {
    return [self succeed];
  }

  NSError *error = nil;
  NSArray<NSArray<NSString *> *> *divided = [FBSimulatorInteraction divideArrayOfMediaPathsInfoPhotosAndVideos:mediaPaths error:&error];
  if (!divided) {
    return [self fail:error];
  }
  NSArray<NSString *> *photos = divided[0];
  NSArray<NSString *> *videos = divided[1];

  return [[self uploadPhotos:photos] uploadVideos:videos];
}

- (instancetype)uploadPhotos:(NSArray *)photoPaths
{
  if (!photoPaths.count) {
    return [self succeed];
  }

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
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

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
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

#pragma mark Private

+ (NSArray<NSArray<NSString *> *> *)divideArrayOfMediaPathsInfoPhotosAndVideos:(NSArray *)mediaPaths error:(NSError **)error
{
  NSMutableArray *photos = [NSMutableArray array];
  NSMutableArray *videos = [NSMutableArray array];

  NSSet *imageUTIs = [NSSet setWithArray:@[(NSString *)kUTTypeImage, (NSString *)kUTTypePNG, (NSString *)kUTTypeJPEG, (NSString *)kUTTypeJPEG2000]];
  NSSet *movieUTIs = [NSSet setWithArray:@[(NSString *)kUTTypeMovie, (NSString *)kUTTypeMPEG4, (NSString *)kUTTypeQuickTimeMovie]];

  for (NSString *path in mediaPaths) {
    NSString *uti = [NSWorkspace.sharedWorkspace typeOfFile:path error:nil];
    if ([imageUTIs containsObject:uti]) {
      [photos addObject:path];
    } else if ([movieUTIs containsObject:uti]) {
      [videos addObject:path];
    } else {
      return [[FBSimulatorError describeFormat:@"%@ has a non media uti of %@", path, uti] fail:error];
    }
  }

  return @[[photos copy], [videos copy]];
}

@end
