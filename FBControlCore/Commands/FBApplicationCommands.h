/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBInstalledApplication;
@class FBProcessInfo;

@protocol FBLaunchedProcess;

/**
 Defines an interface for interacting with iOS Applications.
 */
@protocol FBApplicationCommands <NSObject, FBiOSTargetCommand>

/**
 Installs application at given path on the host.

 @param path the file path of the Application Bundle on the host.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)installApplicationWithPath:(NSString *)path;

/**
 Uninstalls application with given bundle id.

 @param bundleID the bundle id of the application to uninstall.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)uninstallApplicationWithBundleID:(NSString *)bundleID;

/**
 Queries to see if an Application is installed on iOS.

 @param bundleID The Bundle ID of the application.
 @return A future that identifies if the application was installed.
 */
- (FBFuture<NSNumber *> *)isApplicationInstalledWithBundleID:(NSString *)bundleID;

/**
 Launches an Application with the provided Application Launch Configuration.

 @param configuration the Application Launch Configuration to use.
 @return A future that resolves with the launched process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration;

/**
 Kills application with the given bundle identifier.

 @param bundleID bundle ID of installed application
 @return A future that resolves successfully if the bundle was running and is now killed.
 */
- (FBFuture<NSNull *> *)killApplicationWithBundleID:(NSString *)bundleID;

/**
 Fetches a list of the Installed Applications.
 The returned FBBundleDescriptor object is fully JSON Serializable.

 @return A future wrapping a List of Installed Applications.
 */
- (FBFuture<NSArray<FBInstalledApplication *> *> *)installedApplications;

/**
 Fetches the FBInstalledApplication instance by Bundle ID.

 @param bundleID the Bundle ID to fetch an installed application for.
 @return a Future with the installed application.
 */
- (FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(NSString *)bundleID;

/**
 Returns the Applications running on the target.

 @return A future wrapping a mapping of Bundle ID to Process ID.
 */
- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications;

/**
 Returns PID of application with given bundleID

 @param bundleID bundle ID of installed application.
 @return A future wrapping the process id.
 */
- (FBFuture<NSNumber *> *)processIDWithBundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
