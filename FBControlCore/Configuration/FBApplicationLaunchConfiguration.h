/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetOperation.h>
#import <FBControlCore/FBProcessLaunchConfiguration.h>
/**
 Launch Modes for an Applicaton
 */
typedef NS_ENUM(NSUInteger, FBApplicationLaunchMode) {
  FBApplicationLaunchModeFailIfRunning = 0,
  FBApplicationLaunchModeForegroundIfRunning = 1,
  FBApplicationLaunchModeRelaunchIfRunning = 2,
};

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@class FBBundleDescriptor;
@class FBProcessIO;

/**
 A Value object with the information required to launch an Application.
 */
@interface FBApplicationLaunchConfiguration : FBProcessLaunchConfiguration

/**
 Creates and returns a new Configuration with the provided parameters.

 @param bundleID the Bundle ID (CFBundleIdentifier) of the App to Launch. Must not be nil.
 @param bundleName the BundleName (CFBundleName) of the App to Launch. May be nil.
 @param arguments an NSArray<NSString *> of arguments to the process. Must not be nil.
 @param environment a NSDictionary<NSString *, NSString *> of the Environment of the launched Application process. Must not be nil.
 @param waitForDebugger a boolean describing whether the Application should stop after Launch and wait for a debugger to be attached.
 @param io the output configuration for the launched process.
 @return a new Configuration Object with the arguments applied.
 */

- (instancetype)initWithBundleID:(NSString *)bundleID bundleName:(nullable NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger io:(FBProcessIO *)io launchMode:(FBApplicationLaunchMode)launchMode;

/**
 The Bundle ID (CFBundleIdentifier) of the the Application to Launch. Will not be nil.
 */
@property (nonnull, nonatomic, copy, readonly) NSString *bundleID;

/**
 The Name (CFBundleName) of the the Application to Launch. May be nil.
 */
@property (nullable, nonatomic, copy, readonly) NSString *bundleName;

/**
 An enum describing how to launch the application
 */
@property (nonatomic, assign, readonly) FBApplicationLaunchMode launchMode;

/**
 A BOOL signalizing whether the application should wait for debugger to be attached immediately after launch.
 */
@property (nonatomic, assign, readonly) BOOL waitForDebugger;

@end

NS_ASSUME_NONNULL_END
