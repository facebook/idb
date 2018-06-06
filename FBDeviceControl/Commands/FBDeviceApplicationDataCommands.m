// Copyright 2004-present Facebook. All Rights Reserved.

/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target afcCalls:(AFCCalls)afcCalls
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

- (FBFuture<NSNull *> *)copyDataFromContainerOfApplication:(NSString *)bundleID atContainerPath:(NSString *)containerPath toDestinationPath:(NSString *)destinationPath
{
  return [[self
    readFileWithBundleID:bundleID path:containerPath]
    onQueue:self.device.asyncQueue fmap:^FBFuture<NSNull *> *(NSData *fileData) {
     if (![fileData writeToFile:destinationPath atomically:NO]) {
       return [[FBDeviceControlError
        describeFormat:@"Failed write data to file at path %@", destinationPath]
        failFuture];
     }
     return [FBFuture futureWithResult:NSNull.null];
   }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc createDirectory:directoryPath error:error];
    if (!success) {
      return nil;
    }

    return [NSNull null];
  }];
}

- (FBFuture<NSNull *> *)movePath:(NSString *)originPath toPath:(NSString *)destinationPath inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    mach_error_t result = afc.calls.RenamePath(afc.connection, [originPath UTF8String], [destinationPath UTF8String]);
    if (result != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Error when moving path: %d", result]
        fail:error];
    }

    return [NSNull null];
  }];
}

- (FBFuture<NSNull *> *)removePath:(NSString *)path inContainerOfApplication:(NSString *)bundleID
{
  return [self handleWithAFCSessionForBundleID:bundleID operationBlock:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc removePath:path recursively:YES error:error];
    if (!success) {
      return nil;
    }

    return [NSNull null];
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
  return [self.device.amDevice futureForDeviceOperation:^(AMDeviceRef device) {
    AFCConnectionRef afcConnection = NULL;
    int status = self.device.amDevice.calls.CreateHouseArrestService(device, (__bridge CFStringRef _Nonnull)(bundleID), NULL, &afcConnection);
    if (status != 0) {
      NSString *internalMessage = CFBridgingRelease(self.device.amDevice.calls.CopyErrorText(status));
      return [[FBDeviceControlError
        describeFormat:@"Failed to start house_arrest service (%@)", internalMessage]
        failFuture];
    }

    NSError *error = nil;
    FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:afcConnection calls:self.afcCalls];
    id result = operationBlock(connection, &error);
    self.afcCalls.ConnectionClose(afcConnection);
    if (!result) {
      return [FBFuture futureWithError:error];
    }
    return [FBFuture futureWithResult:result];
  }];
}

@end
