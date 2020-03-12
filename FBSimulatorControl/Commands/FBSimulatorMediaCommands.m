/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "NSPredicate+FBSimulatorControl.h"
#import "FBSimulatorMediaCommands.h"

#import <CoreSimulator/SimDevice.h>



@interface FBSimulatorMediaCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorMediaCommands

#pragma mark Initializers

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBiOSTargetCommand Protocol Implementation

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
}

#pragma mark FBSimulatorMediaCommands Protocol

- (FBFuture<NSNull *> *)addMedia:(NSArray<NSURL *> *)mediaFileURLs
{
  NSMutableArray<NSString *> *mediaFilePaths = [NSMutableArray arrayWithCapacity:mediaFileURLs.count];
  for (NSURL *url in mediaFileURLs) {
    [mediaFilePaths addObject:url.path];
  }

  NSError *error;
  if ([self uploadMedia:mediaFilePaths error:&error]) {
    return FBFuture.empty;
  } else {
    return [FBFuture futureWithError:error];
  }
}

#pragma mark Private

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
  if (self.simulator.state != FBiOSTargetStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Simulator must be booted to upload photos, is %@", self.simulator.device.stateString]
      failBool:error];
  }

  for (NSString *path in photoPaths) {
    NSURL *url = [NSURL fileURLWithPath:path];

    NSError *innerError = nil;
    if (![self.simulator.device addPhoto:url error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to upload photo at path %@", path]
        causedBy:innerError]
        failBool:error];
    }
  }
  return YES;
}

- (BOOL)uploadVideos:(NSArray<NSString *> *)videoPaths error:(NSError **)error
{
  if (!videoPaths.count) {
    return YES;
  }
  if (self.simulator.state != FBiOSTargetStateBooted) {
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
