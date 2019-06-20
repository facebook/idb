/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceApplicationDataCommands.h"

#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAFCConnection.h"

@interface FBDeviceApplicationDataCommands ()

@property (nonatomic, strong, readonly) FBDevice *device;
@property (nonatomic, assign, readonly) AFCCalls afcCalls;

@end

@implementation FBDeviceApplicationDataCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target afcCalls:(AFCCalls)afcCalls
{
  return [[self alloc] initWithDevice:target afcCalls:afcCalls];
}

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [self commandsWithTarget:target afcCalls:FBAFCConnection.defaultCalls];
}

- (instancetype)initWithDevice:(FBDevice *)device afcCalls:(AFCCalls)afcCalls
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _afcCalls = afcCalls;

  return self;
}

#pragma mark FBApplicationDataCommands

- (FBFuture<NSData *> *)readFileWithBundleID:(NSString *)bundleID path:(NSString *)path
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSData * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfPath:path error:error];
  }];
}

- (FBFuture<NSNull *> *)copyItemsAtURLs:(NSArray<NSURL *> *)paths toContainerPath:(NSString *)containerPath inBundleID:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSURL *path in paths) {
      BOOL success = [afc copyFromHost:path toContainerPath:containerPath error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSString *> *)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath
{
  return [[self
    readFileWithBundleID:bundleID path:containerPath]
    onQueue:self.device.asyncQueue fmap:^FBFuture<NSString *> *(NSData *fileData) {
     NSError *error;
     if (![fileData writeToFile:destinationPath options:0 error:&error]) {
       return [[[FBDeviceControlError
        describeFormat:@"Failed to write data to file at path %@", destinationPath]
        causedBy:error]
        failFuture];
     }
     return [FBFuture futureWithResult:destinationPath];
   }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc createDirectory:directoryPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSString *originPath in originPaths) {
      BOOL success = [afc renamePath:originPath destination:destinationPath error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSString *path in paths) {
      BOOL success = [afc removePath:path recursively:YES error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)copyDataAtPath:(NSString *)source toContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath
{
  NSURL *path = [NSURL URLWithString:source];
  return [self copyItemsAtURLs:@[path] toContainerPath:containerPath inBundleID:bundleID];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSArray<NSString *> * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfDirectory:path error:error];
  }];
}

#pragma mark Private

- (FBFuture *)handleWithAFCSessionForBundleID:(NSString *)bundleID operationBlock:(id(^)(FBAFCConnection *, NSError **))operationBlock
{
  return [[self.device.amDevice
    houseArrestAFCConnectionForBundleID:bundleID afcCalls:self.afcCalls]
    onQueue:self.device.workQueue pop:^(FBAFCConnection *connection) {
      NSError *error = nil;
      id result = operationBlock(connection, &error);
      if (!result) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:result];
  }];
}

@end
