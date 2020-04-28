/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBTestLaunchConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;
@protocol FBControlCoreLogger;
@protocol FBTestManagerTestReporter;

/**
 The Termination Handle Type.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeTestOperation;

/**
 Commands related to XCTest Execution.
 */
@protocol FBXCTestCommands <NSObject, FBiOSTargetCommand>

/**
 Bootstraps a test run using a Test Launch Configuration.
 It will use the iOS Targets's auxillaryDirectory as a working directory.

 @param testLaunchConfiguration the configuration used for the test launch.
 @param reporter the reporter to report to.
 @param logger the logger to log to.
 @return a Future, wrapping a test operation.
 */
- (FBFuture<id<FBiOSTargetContinuation>> *)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

/**
 Lists the testables for a provided test bundle.

 @param bundlePath the bundle path of the test bundle
 @param timeout a timeout for the listing.
 @return an array of strings for the test names if successful, NO otherwise.
 */
- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(NSString *)appPath;

/**
 Starts 'testmanagerd' connection and creates socket to it.

 @return A future context wrapping the socket transport. The socket transport will be torn down when the context exits
 */
- (FBFutureContext<NSNumber *> *)transportForTestManagerService;

@end

NS_ASSUME_NONNULL_END
