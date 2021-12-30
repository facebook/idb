/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestRunner.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestManagerTestConfiguration;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol FBXCTestExtendedCommands;
@protocol FBXCTestReporter;

/**
 A Runner for test manager managed tests (UITests and Application tests).
 */
@interface FBTestRunStrategy : NSObject <FBXCTestRunner>

/**
 Create and return a new Strategy

 @param target the device target to use for hosting the Application.
 @param configuration the the configuration to use.
 @param reporter the reporter to report to.
 @param logger the logger to use.
 */
+ (instancetype)strategyWithTarget:(id<FBiOSTarget, FBXCTestExtendedCommands>)target configuration:(FBTestManagerTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
