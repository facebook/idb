/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationDataCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorApplicationDataCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationDataCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

#pragma mark FBApplicationDataCommands

- (BOOL)copyDataAtPath:(NSString *)source toContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath error:(NSError **)error
{
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:error];
  if (!dataContainer) {
    return NO;
  }
  NSString *destinationPath = [[dataContainer
    stringByAppendingPathComponent:containerPath]
    stringByAppendingPathComponent:source.lastPathComponent];
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager copyItemAtPath:source toPath:destinationPath error:&innerError]) {
    return [[[FBSimulatorError
     describeFormat:@"Could not copy from %@ to %@", source, destinationPath]
     causedBy:innerError]
     failBool:error];
  }
  return YES;
}

- (BOOL)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath error:(NSError **)error
{
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:error];
  if (!dataContainer) {
    return NO;
  }
  NSString *source = [dataContainer stringByAppendingPathComponent:containerPath];
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager copyItemAtPath:source toPath:destinationPath error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not copy from %@ to %@", source, destinationPath]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

#pragma mark Private

- (NSString *)dataContainerPathForBundleID:(NSString *)bundleID error:(NSError **)error
{
  FBInstalledApplication *application = [[self.simulator installedApplicationWithBundleID:bundleID] await:error];
  if (!application) {
    return nil;
  }
  NSString *dataContainer = application.dataContainer;
  if (!dataContainer) {
    return [[FBSimulatorError
      describeFormat:@"No Data Container for Application %@", application]
      fail:error];
  }
  return dataContainer;
}

@end
