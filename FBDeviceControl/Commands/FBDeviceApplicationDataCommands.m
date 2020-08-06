/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceApplicationDataCommands.h"

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAFCConnection.h"

@interface FBDeviceFileCommands : NSObject <FBiOSTargetFileCommands>

@property (nonatomic, strong, readonly) FBDevice *device;
@property (nonatomic, assign, readonly) AFCCalls afcCalls;

@end

@interface FBDeviceFileCommands_HouseArrest : FBDeviceFileCommands

@property (nonatomic, copy, readonly) NSString *bundleID;

@end

@implementation FBDeviceFileCommands

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

- (FBFuture<NSNull *> *)copyPathsOnHost:(NSArray<NSURL *> *)paths toDestination:(NSString *)destinationPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSURL *path in paths) {
      BOOL success = [afc copyFromHost:path toContainerPath:destinationPath error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath
{
  return [[self
    readFileFromPathInContainer:containerPath]
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

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc createDirectory:directoryPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toDestinationPath:(NSString *)destinationPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSString *originPath in originPaths) {
      BOOL success = [afc renamePath:originPath destination:destinationPath error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    for (NSString *path in paths) {
      BOOL success = [afc removePath:path recursively:YES error:error];
      if (!success) {
        return nil;
      }
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [self handleAFCOperation:^ NSArray<NSString *> * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfDirectory:path error:error];
  }];

}

#pragma mark Private

- (FBFuture<NSData *> *)readFileFromPathInContainer:(NSString *)path
{
  return [self handleAFCOperation:^ NSData * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfPath:path error:error];
  }];
}

- (FBFuture *)handleAFCOperation:(id(^)(FBAFCConnection *, NSError **))operationBlock
{
  return [[self.device
    startAFCService:@"com.apple.afc"]
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

@implementation FBDeviceFileCommands_HouseArrest

- (instancetype)initWithDevice:(FBDevice *)device afcCalls:(AFCCalls)afcCalls bundleID:(NSString *)bundleID
{
  self = [super initWithDevice:device afcCalls:afcCalls];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;

  return self;
}

- (FBFuture *)handleAFCOperation:(id(^)(FBAFCConnection *, NSError **))operationBlock
{
  return [[self.device
    houseArrestAFCConnectionForBundleID:self.bundleID afcCalls:self.afcCalls]
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

- (id<FBiOSTargetFileCommands>)fileCommandsForContainerApplication:(NSString *)bundleID
{
  return [[FBDeviceFileCommands_HouseArrest alloc] initWithDevice:self.device afcCalls:self.afcCalls bundleID:bundleID];
}

- (id<FBiOSTargetFileCommands>)fileCommandsForRootFilesystem
{
  return [[FBDeviceFileCommands alloc] initWithDevice:self.device afcCalls:self.afcCalls];
}

@end
