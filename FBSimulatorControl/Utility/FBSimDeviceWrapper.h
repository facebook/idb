/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 ObjC helper that wraps SimDevice / SimRuntime calls.
 Swift files in this mixed module cannot see the full CoreSimulator interface
 (headers are private and have no module map). This class bridges the gap.
 */
@interface FBSimDeviceWrapper : NSObject

#pragma mark - Property Access

/// Returns SimDevice.runtime.root for the given device.
+ (nullable NSString *)runtimeRootForDevice:(id)device;

#pragma mark - Capability Checks

/// Returns YES if the device responds to -simulateMemoryWarning.
+ (BOOL)deviceCanSimulateMemoryWarning:(id)device;

/// Returns YES if the device responds to -setLocationWithLatitude:andLongitude:error:.
+ (BOOL)deviceCanSetLocation:(id)device;

/// Returns YES if the device responds to -sendPushNotificationForBundleID:jsonPayload:error:.
+ (BOOL)deviceCanSendPushNotification:(id)device;

#pragma mark - Actions

/// Calls -[SimDevice simulateMemoryWarning] on the given device.
+ (void)simulateMemoryWarningOnDevice:(id)device;

/// Calls -[SimDevice setLocationWithLatitude:andLongitude:error:] on the given device.
+ (BOOL)setLocationOnDevice:(id)device latitude:(double)latitude longitude:(double)longitude error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice sendPushNotificationForBundleID:jsonPayload:error:] on the given device.
+ (void)sendPushNotificationOnDevice:(id)device bundleID:(NSString *)bundleID jsonPayload:(NSDictionary<NSString *, id> *)payload error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice installApplication:withOptions:error:] on the given device.
+ (BOOL)installApplicationOnDevice:(id)device appURL:(NSURL *)appURL options:(NSDictionary<NSString *, id> *)options error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice uninstallApplication:withOptions:error:] on the given device.
+ (BOOL)uninstallApplicationOnDevice:(id)device bundleID:(NSString *)bundleID options:(nullable NSDictionary *)options error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice terminateApplicationWithID:error:] on the given device.
+ (BOOL)terminateApplicationOnDevice:(id)device bundleID:(NSString *)bundleID error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice installedAppsWithError:] on the given device.
+ (nullable NSDictionary<NSString *, id> *)installedAppsOnDevice:(id)device error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice applicationIsInstalled:type:error:] on the given device.
+ (BOOL)applicationIsInstalledOnDevice:(id)device bundleID:(NSString *)bundleID typeOut:(NSString *_Nullable *_Nullable)typeOut error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice propertiesOfApplication:error:] on the given device.
+ (nullable NSDictionary<NSString *, id> *)propertiesOfApplicationOnDevice:(id)device bundleID:(NSString *)bundleID error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice launchApplicationAsyncWithID:options:completionQueue:completionHandler:] on the given device.
+ (void)launchApplicationAsyncOnDevice:(id)device bundleID:(NSString *)bundleID options:(NSDictionary<NSString *, id> *)options completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *_Nullable error, pid_t pid))completionHandler;

/// Calls -[SimDevice spawnAsyncWithPath:options:terminationQueue:terminationHandler:completionQueue:completionHandler:] on the given device.
+ (void)spawnAsyncOnDevice:(id)device path:(NSString *)path options:(NSDictionary<NSString *, id> *)options terminationQueue:(dispatch_queue_t)terminationQueue terminationHandler:(void (^)(int stat_loc))terminationHandler completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(NSError *_Nullable error, pid_t pid))completionHandler;

#pragma mark - Media

/// Calls -[SimDevice addPhoto:error:] on the given device.
+ (BOOL)addPhotoOnDevice:(id)device url:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice addVideo:error:] on the given device.
+ (BOOL)addVideoOnDevice:(id)device url:(NSURL *)url error:(NSError *_Nullable *_Nullable)error;

/// Calls -[SimDevice addMedia:error:] on the given device.
+ (BOOL)addMediaOnDevice:(id)device urls:(NSArray<NSURL *> *)urls error:(NSError *_Nullable *_Nullable)error;

/// Returns SimDevice.stateString for the given device.
+ (nullable NSString *)stateStringForDevice:(id)device;

@end

NS_ASSUME_NONNULL_END
