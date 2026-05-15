/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimDeviceWrapper.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

@implementation FBSimDeviceWrapper

#pragma mark - Property Access

+ (NSString *)runtimeRootForDevice:(id)device
{
  SimDevice *simDevice = (SimDevice *)device;
  return simDevice.runtime.root;
}

#pragma mark - Capability Checks

+ (BOOL)deviceCanSimulateMemoryWarning:(id)device
{
  return [device respondsToSelector:@selector(simulateMemoryWarning)];
}

+ (BOOL)deviceCanSetLocation:(id)device
{
  return [device respondsToSelector:@selector(setLocationWithLatitude:andLongitude:error:)];
}

+ (BOOL)deviceCanSendPushNotification:(id)device
{
  return [device respondsToSelector:@selector(sendPushNotificationForBundleID:jsonPayload:error:)];
}

#pragma mark - Actions

+ (void)simulateMemoryWarningOnDevice:(id)device
{
  [(SimDevice *)device simulateMemoryWarning];
}

+ (BOOL)setLocationOnDevice:(id)device latitude:(double)latitude longitude:(double)longitude error:(NSError **)error
{
  return [(SimDevice *)device setLocationWithLatitude:latitude andLongitude:longitude error:error];
}

+ (void)sendPushNotificationOnDevice:(id)device bundleID:(NSString *)bundleID jsonPayload:(NSDictionary<NSString *, id> *)payload error:(NSError **)error
{
  [(SimDevice *)device sendPushNotificationForBundleID:bundleID jsonPayload:payload error:error];
}

+ (BOOL)installApplicationOnDevice:(id)device appURL:(NSURL *)appURL options:(NSDictionary<NSString *, id> *)options error:(NSError **)error
{
  return [(SimDevice *)device installApplication:appURL withOptions:options error:error];
}

+ (BOOL)uninstallApplicationOnDevice:(id)device bundleID:(NSString *)bundleID options:(NSDictionary *)options error:(NSError **)error
{
  return [(SimDevice *)device uninstallApplication:bundleID withOptions:options error:error];
}

+ (BOOL)terminateApplicationOnDevice:(id)device bundleID:(NSString *)bundleID error:(NSError **)error
{
  return [(SimDevice *)device terminateApplicationWithID:bundleID error:error];
}

+ (NSDictionary<NSString *, id> *)installedAppsOnDevice:(id)device error:(NSError **)error
{
  return [(SimDevice *)device installedAppsWithError:error];
}

+ (BOOL)applicationIsInstalledOnDevice:(id)device bundleID:(NSString *)bundleID typeOut:(NSString **)typeOut error:(NSError **)error
{
  return [(SimDevice *)device applicationIsInstalled:bundleID type:typeOut error:error];
}

+ (NSDictionary<NSString *, id> *)propertiesOfApplicationOnDevice:(id)device bundleID:(NSString *)bundleID error:(NSError **)error
{
  return [(SimDevice *)device propertiesOfApplication:bundleID error:error];
}

+ (void)launchApplicationAsyncOnDevice:(id)device bundleID:(NSString *)bundleID options:(NSDictionary<NSString *, id> *)options completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *_Nullable, pid_t))completionHandler
{
  [(SimDevice *)device launchApplicationAsyncWithID:bundleID options:options completionQueue:completionQueue completionHandler:completionHandler];
}

+ (void)spawnAsyncOnDevice:(id)device path:(NSString *)path options:(NSDictionary<NSString *, id> *)options terminationQueue:(dispatch_queue_t)terminationQueue terminationHandler:(void (^)(int))terminationHandler completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *_Nullable, pid_t))completionHandler
{
  [(SimDevice *)device
   spawnAsyncWithPath:path
   options:options
   terminationQueue:terminationQueue
   terminationHandler:terminationHandler
   completionQueue:completionQueue
   completionHandler:completionHandler];
}

#pragma mark - Media

+ (BOOL)addPhotoOnDevice:(id)device url:(NSURL *)url error:(NSError **)error
{
  return [(SimDevice *)device addPhoto:url error:error];
}

+ (BOOL)addVideoOnDevice:(id)device url:(NSURL *)url error:(NSError **)error
{
  return [(SimDevice *)device addVideo:url error:error];
}

+ (BOOL)addMediaOnDevice:(id)device urls:(NSArray<NSURL *> *)urls error:(NSError **)error
{
  return [(SimDevice *)device addMedia:urls error:error];
}

+ (NSString *)stateStringForDevice:(id)device
{
  return [(SimDevice *)device stateString];
}

@end
