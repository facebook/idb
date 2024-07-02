/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;

@protocol FBiOSTarget;

/**
 Builds an xcodebuild invocation as a subprocess.
 */
@interface FBXcodeBuildOperation : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param udid the udid of the target.
 @param configuration the configuration to use.
 @param xcodeBuildPath the path to xcodebuild.
 @param testRunFilePath the path to the xcodebuild.xctestrun file
 @param simDeviceSetPath an optional path to the simulator device set
 @param macOSTestShimPath this should be provided if simDeviceSetPath is non-nil
 @param queue the queue to use for serialization.
 @param logger the logger to log to.
 @return a future that resolves when the task has launched.
 */
+ (FBFuture<FBProcess *> *)operationWithUDID:(NSString *)udid configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath simDeviceSet:(nullable NSString *)simDeviceSetPath macOSTestShimPath:(nullable NSString *)macOSTestShimPath queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 The xctest.xctestrun properties for a test launch.

 @param testLaunch the test launch to base off.
 @return the xctest.xctestrun properties.
 */
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch;

/**
 Create a xctestrun file from a test launch.

 @param directory the directory where the xctestrun file will be written to.
 @param configuration  the test launch to base off.
 @param error an error out for any error that occurs.
 @return the path of the xctestrun file created.
 */
+ (nullable NSString *)createXCTestRunFileAt:(NSString *)directory fromConfiguration:(FBTestLaunchConfiguration *)configuration error:(NSError **)error;

/**
 Get the xcodebuild path.

 @param error an error out for any error that occurs.
 @return xcodebuild path
 */
+ (NSString *)xcodeBuildPathWithError:(NSError **)error;

/**
 Terminates all reparented xcodebuild processes.

 @param udid the udid of the target.
 @param processFetcher the process fetcher to use.
 @param queue the termination queue
 @param logger a logger to log to.
 @return a Future that resolves when processes have exited.
 */
+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 A helper method for overwriting xcTestRunProperties.
 Creates a new properties dictionary with values from baseProperties
 overwritten with values from newProperties. It overwrites values only
 for existing keys. It assumes that the dictionary has XCTestRun file
 format and that base has a single test with bundle id StubBundleId.

 @param baseProperties base properties
 @param newProperties base properties will be overwritten with newProperties
 @returns a new xcTestRunProperites with
 */
+ (NSDictionary *)overwriteXCTestRunPropertiesWithBaseProperties:(NSDictionary<NSString *, id> *)baseProperties newProperties:(NSDictionary<NSString *, id> *)newProperties;

/**
 Confirms the proper exit of the provided xcodebuild operation.
 
 @param task the task to monitor.
 @param configuration the configuration of the launched process.
 @param reporter the reporter to report to
 @param target the target for which the task was launched.
 @param logger the logger to log to.
 @return a checked exit of the task.
 */
+ (FBFuture<NSNull *> *)confirmExitOfXcodebuildOperation:(FBProcess *)task configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter target:(id<FBiOSTarget>)target logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
