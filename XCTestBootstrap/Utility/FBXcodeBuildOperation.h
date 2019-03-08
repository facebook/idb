/**
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 @param queue the queue to use for serialization.
 @param logger the logger to log to.
 @return a future that resolves when the task has launched.
 */
+ (FBFuture<FBTask *> *)operationWithUDID:(NSString *)udid configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 The xctest.xctestrun properties for a test launch.

 @param testLaunch the test launch to base off.
 @return the xctest.xctestrun properties.
 */
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)xctestRunProperties:(FBTestLaunchConfiguration *)testLaunch;

/**
 Terminates all reparented xcodebuild processes.

 @param udid the udid of the target.
 @param processFetcher the process fetcher to use.
 @param queue the termination queue
 @param logger a logger to log to.
 @return a Future that resolves when processes have exited.
 */
+ (FBFuture<NSArray<FBProcessInfo *> *> *)terminateAbandonedXcodebuildProcessesForUDID:(NSString *)udid processFetcher:(FBProcessFetcher *)processFetcher queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
