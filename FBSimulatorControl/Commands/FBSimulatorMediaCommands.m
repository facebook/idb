/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorMediaCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
  return [self predicateForPathsMatchingTypes:@[UTTypeMovie, UTTypeMPEG4Movie, UTTypeQuickTimeMovie]];
}

+ (NSPredicate *)predicateForPhotoPaths
{
  // UTTypeImage already covers PNG/JPEG/JPEG2000 (they conform to public.image),
  // which is the behaviour we want when filtering media paths.
  return [self predicateForPathsMatchingTypes:@[UTTypeImage]];
}

+ (NSPredicate *)predicateForContactPaths
{
  return [self predicateForPathsMatchingTypes:@[UTTypeVCard]];
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

+ (NSPredicate *)predicateForPathsMatchingTypes:(NSArray<UTType *> *)types
{
  return [NSPredicate predicateWithBlock:^ BOOL (NSURL *url, NSDictionary *_) {
    UTType *type = nil;
    if (![url getResourceValue:&type forKey:NSURLContentTypeKey error:nil] || !type) {
      return NO;
    }
    for (UTType *candidate in types) {
      if ([type conformsToType:candidate]) {
        return YES;
      }
    }
    return NO;
  }];
}

@end
