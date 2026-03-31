/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@class FBLogicTestConfiguration;

@protocol FBiOSTarget;
@protocol FBProcessSpawnCommands;
@protocol FBXCTestExtendedCommands;

/**
 A Runner for Logic Tests
 */
@interface FBLogicTestRunStrategy : NSObject <FBXCTestRunner>

/**
 Creates a Logic Test Runner for iOS with the Provided Parameters.

 @param target the target to run against.
 @param configuration the Configuration to use.
 @param reporter the reporter to report to.
 @param logger the logger to use.
 @return a new Logic Test Strategy.
 */
- (nonnull instancetype)initWithTarget:(nonnull id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands>)target configuration:(nonnull FBLogicTestConfiguration *)configuration reporter:(nonnull id<FBLogicXCTestReporter>)reporter logger:(nonnull id<FBControlCoreLogger>)logger;

@end
