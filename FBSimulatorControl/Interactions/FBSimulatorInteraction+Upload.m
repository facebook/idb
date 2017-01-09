/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Upload.h"

#import "FBSimulatorInteraction+Private.h"
#import "FBUploadMediaStrategy.h"

@implementation FBSimulatorInteraction (Upload)

- (instancetype)uploadMedia:(NSArray<NSString *> *)mediaPaths
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBUploadMediaStrategy strategyWithSimulator:simulator] uploadMedia:mediaPaths error:error];
  }];
}

- (instancetype)uploadPhotos:(NSArray<NSString *> *)photoPaths
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBUploadMediaStrategy strategyWithSimulator:simulator] uploadPhotos:photoPaths error:error];
  }];
}

- (instancetype)uploadVideos:(NSArray<NSString *> *)videoPaths
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBUploadMediaStrategy strategyWithSimulator:simulator] uploadVideos:videoPaths error:error];
  }];
}

@end
