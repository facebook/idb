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

- (FBFuture<NSNull *> *)copyDataAtPath:(NSString *)source toContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath
{
  NSURL *url = [NSURL fileURLWithPath:source];
  return [self copyItemsAtURLs:@[url] toContainerPath:containerPath inBundleID:bundleID];
}

- (FBFuture<NSNull *> *)copyItemsAtURLs:(NSArray<NSURL *> *)paths toContainerPath:(NSString *)containerPath inBundleID:(NSString *)bundleID
{
  NSError *error;
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:&error];
  if (!dataContainer) {
    return [[[FBSimulatorError
              describeFormat:@"Couldn't obtain data container for bundle id %@", bundleID]
              causedBy:error]
              failFuture];
  }
  NSURL *basePathURL =  [NSURL fileURLWithPathComponents:@[dataContainer, containerPath]];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  for (NSURL *url in paths) {
    NSURL *destURL = [basePathURL URLByAppendingPathComponent:url.lastPathComponent];
    if (![fileManager copyItemAtURL:url toURL:destURL error:&error]) {
      return [[[FBSimulatorError
                describeFormat:@"Could not copy from %@ to %@", url, destURL]
                causedBy:error]
                failFuture];
    }
  }
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath
{
  NSError *error;
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:&error];
  if (!dataContainer) {
    return [[[FBSimulatorError
      describeFormat:@"Couldn't obtain data container for bundle id %@", bundleID]
      causedBy:error]
      failFuture];
  }
  NSString *source = [dataContainer stringByAppendingPathComponent:containerPath];
  if (![NSFileManager.defaultManager copyItemAtPath:source toPath:destinationPath error:&error]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not copy from %@ to %@", source, destinationPath]
      causedBy:error]
      failFuture];
  }
  return [FBFuture futureWithResult:NSNull.null];
}

- (nonnull FBFuture<NSNull *> *)createDirectory:(nonnull NSString *)directoryPath inContainerOfApplication:(nonnull NSString *)bundleID
{
  NSError *error;
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:&error];
  if (!dataContainer) {
    return [[[FBSimulatorError
              describeFormat:@"Couldn't obtain data container for bundle id %@", bundleID]
             causedBy:error]
            failFuture];
  }
  NSString *fullPath = [dataContainer stringByAppendingPathComponent:directoryPath];
  if (![NSFileManager.defaultManager createDirectoryAtPath:fullPath
                               withIntermediateDirectories:YES
                                                attributes:nil error:&error]) {
    return [[[FBSimulatorError
              describeFormat:@"Could not create directory %@ in container %@", directoryPath, dataContainer]
             causedBy:error]
            failFuture];
  }
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)movePath:(NSString *)originPath toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  NSError *error;
  NSString *dataContainer = [self dataContainerPathForBundleID:bundleID error:&error];
  if (!dataContainer) {
    return [[[FBSimulatorError
              describeFormat:@"Couldn't obtain data container for bundle id %@", bundleID]
              causedBy:error]
              failFuture];
  }
  originPath = [dataContainer stringByAppendingPathComponent:originPath];
  destinationPath = [dataContainer stringByAppendingPathComponent:destinationPath];
  if (![NSFileManager.defaultManager moveItemAtPath:originPath toPath:destinationPath error:&error]) {
    return [[[FBSimulatorError
              describeFormat:@"Could not remove item at %@ to %@", originPath, destinationPath]
              causedBy:error]
              failFuture];
  }
  return [FBFuture futureWithResult:NSNull.null];
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
