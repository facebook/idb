/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBTestLaunchConfiguration;

@protocol FBXCTestReporter;
@protocol FBXCTestExtendedCommands;

/**
 A Strategy that encompasses a Single Test Run on a Simulator.
 */
@interface FBManagedTestRunStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a new Test Run Strategy.

 @param target the Target to use.
 @param configuration the configuration to use.
 @param reporter the reporter to use.
 @param logger the logger to use.
 @return a new Test Run Strategy instance.
 */
+ (FBFuture<NSNull *> *)runToCompletionWithTarget:(id<FBiOSTarget, FBXCTestExtendedCommands>)target configuration:(FBTestLaunchConfiguration *)configuration codesign:(nullable FBCodesignProvider *)codesign workingDirectory:(NSString *)workingDirectory reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
