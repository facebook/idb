/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
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
 Commands to perform on an iOS Target, related to XCTest.
 */
@protocol FBXCTestCommands <NSObject>

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
- (FBFuture<NSArray<NSString *> *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
