/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

@class FBApplicationTestConfiguration;
@class FBSimulator;

/**
 A Runner for Application Tests.
 */
@interface FBApplicationTestRunStrategy : NSObject <FBXCTestRunner>

/**
 Create and return a new Strategy for Application Tests on iOS.

 @param simulator the Simulator to use for hosting the Application.
 @param configuration the the configuration to use.
 @param reporter the reporter to report to.
 @param logger the logger to use.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
