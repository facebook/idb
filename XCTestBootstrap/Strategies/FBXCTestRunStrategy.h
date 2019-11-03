/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBTestManager;
@protocol FBXCTestPreparationStrategy;
@protocol FBTestManagerTestReporter;

/**
 Strategy used to run an injected XCTest bundle in an Application and attach the 'testmanagerd' daemon to it.
 */
@interface FBXCTestRunStrategy : NSObject

#pragma mark Initializers

/**
 Convenience constructor

 @param iosTarget ios target used to run tests.
 @param testPrepareStrategy test preparation strategy used to prepare device to test.
 @param reporter the Reporter to report test progress to.
 @param logger the logger object to log events to, may be nil.
 @return operator
 */
+ (instancetype)strategyWithIOSTarget:(id<FBiOSTarget>)iosTarget testPrepareStrategy:(id<FBXCTestPreparationStrategy>)testPrepareStrategy reporter:(nullable id<FBTestManagerTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public Methods.

/**
 Starts testing session

 @param applicationLaunchConfiguration application launch configuration used to start test runner
 @return A future that resolves with the Test Manager
 */
- (FBFuture<FBTestManager *> *)startTestManagerWithApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration;

@end

NS_ASSUME_NONNULL_END
