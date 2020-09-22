/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorMediaCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <AppKit/AppKit.h>

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
  NSError *error;
  if ([self uploadMedia:mediaFileURLs error:&error]) {
    return FBFuture.empty;
  } else {
    return [FBFuture futureWithError:error];
  }
}

+ (NSPredicate *)predicateForVideoPaths
{
  return [self predicateForPathsMatchingUTIs:@[(NSString *)kUTTypeMovie, (NSString *)kUTTypeMPEG4, (NSString *)kUTTypeQuickTimeMovie]];
}

+ (NSPredicate *)predicateForPhotoPaths
{
  return [self predicateForPathsMatchingUTIs:@[(NSString *)kUTTypeImage, (NSString *)kUTTypePNG, (NSString *)kUTTypeJPEG, (NSString *)kUTTypeJPEG2000]];
}

+ (NSPredicate *)predicateForContactPaths
{
  return [self predicateForPathsMatchingUTIs:@[(NSString *)kUTTypeVCard]];
}

+ (NSPredicate *)predicateForMediaPaths
{
  return [NSCompoundPredicate orPredicateWithSubpredicates:@[
    self.predicateForVideoPaths,
    self.predicateForPhotoPaths,
    self.predicateForContactPaths,
  ]];
}

#pragma mark Private

- (BOOL)uploadMedia:(NSArray<NSURL *> *)mediaFileURLs error:(NSError **)error
{
  if (!mediaFileURLs.count) {
    return [[FBSimulatorError
      describe:@"Cannot upload media, none was provided"]
      failBool:error];
  }

  NSArray<NSURL *> *unknown = [mediaFileURLs filteredArrayUsingPredicate:[NSCompoundPredicate notPredicateWithSubpredicate:FBSimulatorMediaCommands.predicateForMediaPaths]];
  if (unknown.count > 0) {
    return [[FBSimulatorError
      describeFormat:@"%@ not a known media path", unknown]
      failBool:error];
  }

  if (self.simulator.state != FBiOSTargetStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Simulator must be booted to upload photos, is %@", self.simulator.device.stateString]
      failBool:error];
  }

  for (NSURL *url in [mediaFileURLs filteredArrayUsingPredicate:FBSimulatorMediaCommands.predicateForPhotoPaths]) {
    NSError *innerError = nil;
    if (![self.simulator.device addPhoto:url error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to add photo %@", url]
        causedBy:innerError]
        failBool:error];
    }
  }

  for (NSURL *url in [mediaFileURLs filteredArrayUsingPredicate:FBSimulatorMediaCommands.predicateForVideoPaths]) {
    NSError *innerError = nil;
    if (![self.simulator.device addVideo:url error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to add video %@", url]
        causedBy:innerError]
        failBool:error];
    }
  }

  NSArray<NSURL *> *contacts = [mediaFileURLs filteredArrayUsingPredicate:FBSimulatorMediaCommands.predicateForContactPaths];
  if (contacts.count > 0) {
    NSError *innerError = nil;
    if (![self.simulator.device addMedia:contacts error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to add contacts %@", contacts]
        causedBy:innerError]
        failBool:error];
    }
  }

  return YES;
}

+ (NSPredicate *)predicateForPathsMatchingUTIs:(NSArray<NSString *> *)utis
{
  NSSet<NSString *> *utiSet = [NSSet setWithArray:utis];
  NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
  return [NSPredicate predicateWithBlock:^ BOOL (NSURL *url, NSDictionary *_) {
    NSString *uti = [workspace typeOfFile:url.path error:nil];
    return [utiSet containsObject:uti];
  }];
}

@end
