/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDebugDescribeable.h>
#import <FBControlCore/FBiOSTargetAction.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBProcessLaunchConfiguration.h>

@class FBApplicationDescriptor;
@class FBBinaryDescriptor;
@class FBProcessOutputConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for an Application Launch.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeApplicationLaunch;

/**
 A Value object with the information required to launch an Application.
 */
@interface FBApplicationLaunchConfiguration : FBProcessLaunchConfiguration <FBiOSTargetAction>

/**
 Creates and returns a new Configuration with the provided parameters.

 @param application the Application to Launch.
 @param arguments an NSArray<NSString *> of arguments to the process. Must not be nil.
 @param environment a NSDictionary<NSString *, NSString *> of the Environment of the launched Application process. Must not be nil.
 @param waitForDebugger a boolean describing whether the Application should stop after Launch and wait for a debugger to be attached.
 @param output the output configuration for the launched process.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithApplication:(FBApplicationDescriptor *)application arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output;

/**
 Creates and returns a new Configuration with the provided parameters.

 @param bundleID the Bundle ID (CFBundleIdentifier) of the App to Launch. Must not be nil.
 @param bundleName the BundleName (CFBundleName) of the App to Launch. May be nil.
 @param arguments an NSArray<NSString *> of arguments to the process. Must not be nil.
 @param environment a NSDictionary<NSString *, NSString *> of the Environment of the launched Application process. Must not be nil.
 @param waitForDebugger a boolean describing whether the Application should stop after Launch and wait for a debugger to be attached.
 @param output the output configuration for the launched process.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithBundleID:(NSString *)bundleID bundleName:(nullable NSString *)bundleName arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger output:(FBProcessOutputConfiguration *)output;

/**
 Adds output configuration.

 @param output output configuration
 @return new application launch configuration with changes applied.
 */
- (instancetype)withOutput:(FBProcessOutputConfiguration *)output;

/**
 The Bundle ID (CFBundleIdentifier) of the the Application to Launch. Will not be nil.
 */
@property (nonnull, nonatomic, copy, readonly) NSString *bundleID;

/**
 The Name (CFBundleName) of the the Application to Launch. May be nil.
 */
@property (nullable, nonatomic, copy, readonly) NSString *bundleName;

/**
 A BOOL signalizing whether the application should wait for debugger to be attached immediately after launch.
 */
@property (nonatomic, assign, readonly) BOOL waitForDebugger;

@end

NS_ASSUME_NONNULL_END
