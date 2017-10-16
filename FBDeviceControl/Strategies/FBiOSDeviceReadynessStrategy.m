/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSDeviceReadynessStrategy.h"

#import <DTDeviceKitBase/DTDKRemoteDeviceConsoleController.h>
#import <DTDeviceKitBase/DTDKRemoteDeviceToken.h>
#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import "FBDeviceControlError.h"

#import <FBControlCore/FBControlCore.h>

@interface FBiOSDeviceReadynessStrategy ()

@property (nonatomic, strong, readonly) DVTiOSDevice *device;
@property (nonatomic, assign, readonly) dispatch_queue_t queue;

@end

@implementation FBiOSDeviceReadynessStrategy

- (instancetype)initWithDVTDevice:(DVTiOSDevice *)device workQueue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _queue = queue;

  return self;
}

+ (instancetype)strategyWithDVTDevice:(DVTiOSDevice *)device workQueue:(dispatch_queue_t)queue
{
  return [[FBiOSDeviceReadynessStrategy alloc] initWithDVTDevice:device workQueue:queue];
}

- (BOOL)isReadyForDebuggingWithError:(NSError **)error
{
  if (!self.device.supportsXPCServiceDebugging) {
    return [[FBDeviceControlError describe:@"Device does not support XPC service debugging"] failBool:error];
  } else if (!self.device.serviceHubProcessControlChannel) {
    return [[FBDeviceControlError describe:@"Failed to create HUB control channel"] failBool:error];
  } else {
    return YES;
  }
}

#pragma mark - FBFuture

- (FBFuture<NSNull *> *)waitForDevicePasscodeUnlock
{
  return [FBFuture onQueue:self.queue resolveWhen:^BOOL {
    return ![self.device isPasscodeLocked];
  }];
}

- (FBFuture<NSNull *> *)waitForDeviceAvailable
{
  return [FBFuture onQueue:self.queue resolveWhen:^BOOL {
    return self.device.isAvailable;
  }];
}

- (FBFuture<NSNull *> *)waitForDeviceReady
{
  return [FBFuture onQueue:self.queue resolveWhen:^BOOL {
    return self.device.deviceReady;
  }];
}

- (FBFuture<NSNull *> *)waitForDevicePreLaunchConsole
{
  __block NSUInteger preLaunchLogLength;
  __block NSString *preLaunchConsoleString;

  return [FBFuture onQueue:self.queue resolveWhen:^BOOL {
    NSString *log = [self.device.token.deviceConsoleController.consoleString copy];
    if (log.length == 0) {
      return NO;
    }

    // Waiting for console to load all entries
    if (log.length != preLaunchLogLength) {
      preLaunchLogLength = log.length;
      return NO;
    }

    preLaunchConsoleString = log;
    return YES;
  }];
}

- (FBFuture<NSNull *> *)waitForDeviceReadyToDebug
{
  return [[[FBFuture futureWithFutures:@[
    [self waitForDevicePasscodeUnlock],
    [self waitForDeviceAvailable],
    [self waitForDeviceReady]
  ]] onQueue:self.queue fmap:^FBFuture *(id _) {
    return [self waitForDevicePreLaunchConsole];
  }] onQueue:self.queue fmap:^FBFuture *(id _) {
    return [FBFuture onQueue:self.queue resolveValue:^id (NSError **error) {
      return [self isReadyForDebuggingWithError:error] ? NSNull.null : nil;
    }];
  }];
}

@end
