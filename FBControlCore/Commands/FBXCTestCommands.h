/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
@protocol FBXCTestReporter;

/**
 Commands related to XCTest Execution via the "regular" managed test execution.
 */
@protocol FBXCTestCommands <NSObject, FBiOSTargetCommand>

/**
 Bootstraps a test run using a Test Launch Configuration.
 It will use the iOS Targets's auxillaryDirectory as a working directory.

 @param testLaunchConfiguration the configuration used for the test launch.
 @param reporter the reporter to report to.
 @param logger the logger to log to.
 @return a Future that resolves when the test run has completed.
 */
- (FBFuture<NSNull *> *)runTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

/**
 Supported on *some* platforms.
 These commands require extensive platform support.
 */
@protocol FBXCTestExtendedCommands <FBXCTestCommands>

/**
 Lists the testables for a provided test bundle.

 @param bundlePath the bundle path of the test bundle
 @param timeout a timeout for the listing.
 @return an array of strings for the test names if successful, NO otherwise.
 */
- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout withAppAtPath:(nullable NSString *)appPath;

/**
 Returns the platform specific shims.
 */
- (FBFuture<NSString *> *)extendedTestShim;

/**
 Starts 'testmanagerd' connection and creates socket to it.
 This can then be used in the process of test execution mediation.

 @return A future context wrapping the socket transport. The socket transport will be torn down when the context exits
 */
- (FBFutureContext<NSNumber *> *)transportForTestManagerService;

/**
 The Path to the xctest executable.
 */
@property (nonatomic, copy, readonly) NSString *xctestPath;

@end

NS_ASSUME_NONNULL_END
