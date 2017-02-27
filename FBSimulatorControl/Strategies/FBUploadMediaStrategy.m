/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBUploadMediaStrategy.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBAddVideoPolyfill.h"

@interface FBUploadMediaStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBAddVideoStrategy_CoreSimulator : FBUploadMediaStrategy

@end

@interface FBAddVideoStrategy_Polyfill : FBUploadMediaStrategy

@end

@implementation FBUploadMediaStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  Class strategyClass = [simulator.device respondsToSelector:@selector(addVideo:error:)]
    ? FBAddVideoStrategy_CoreSimulator.class
    : FBAddVideoStrategy_Polyfill.class;

  return [[strategyClass alloc] initWithSimulator:simulator];
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

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (BOOL)uploadMedia:(NSArray<NSString *> *)mediaPaths error:(NSError **)error
{
  if (!mediaPaths.count) {
    return YES;
  }

  NSArray<NSString *> *unknown = [mediaPaths filteredArrayUsingPredicate:[NSCompoundPredicate notPredicateWithSubpredicate:NSPredicate.predicateForMediaPaths]];
  if (unknown.count > 0) {
    return [[FBSimulatorError
      describeFormat:@"%@ not a media path", unknown]
      failBool:error];
  }

  NSArray<NSString *> *photos = [mediaPaths filteredArrayUsingPredicate:NSPredicate.predicateForPhotoPaths];
  NSArray<NSString *> *videos = [mediaPaths filteredArrayUsingPredicate:NSPredicate.predicateForVideoPaths];

  return [self uploadPhotos:photos error:error] && [self uploadVideos:videos error:error];
}

- (BOOL)uploadPhotos:(NSArray<NSString *> *)photoPaths error:(NSError **)error
{
  if (!photoPaths.count) {
    return YES;
  }
  if (self.simulator.state != FBSimulatorStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Simulator must be booted to upload photos, is %@", self.simulator.device.stateString]
      failBool:error];
  }

  for (NSString *path in photoPaths) {
    NSURL *url = [NSURL fileURLWithPath:path];

    NSError *innerError = nil;
    if (![self.simulator.device addPhoto:url error:&innerError]) {
      return [[[FBSimulatorError describeFormat:@"Failed to upload photo at path %@", path] causedBy:innerError] failBool:error];
    }
  }
  return YES;
}

- (BOOL)uploadVideos:(NSArray<NSString *> *)videoPaths error:(NSError **)error
{
  if (!videoPaths.count) {
    return YES;
  }
  if (self.simulator.state != FBSimulatorStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Simulator must be booted to upload videos, is %@", self.simulator.device.stateString]
      failBool:error];
  }

  NSError *innerError = nil;
  BOOL success = [self addVideos:videoPaths error:&innerError];
  if (!success) {
    return [[[FBSimulatorError describeFormat:@"Failed to upload videos at paths %@", videoPaths]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}


@end

@implementation FBAddVideoStrategy_CoreSimulator

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  for (NSString *path in paths) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *innerError = nil;
    if (![self.simulator.device addVideo:url error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to upload video at path %@", path]
        causedBy:innerError]
        failBool:error];
    }
  }
  return YES;
}

@end

@implementation FBAddVideoStrategy_Polyfill

- (BOOL)addVideos:(NSArray<NSString *> *)paths error:(NSError **)error
{
  return [[FBAddVideoPolyfill withSimulator:self.simulator] addVideos:paths error:error];
}

@end
