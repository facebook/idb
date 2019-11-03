/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestRunnerConfiguration;
@protocol FBiOSTarget;
@protocol FBFileManager;
@protocol FBCodesignProvider;

/**
 A protocol that defines an interface for preparing a test configuration.
 */
@protocol FBXCTestPreparationStrategy

#pragma mark Initializers

/**
 Creates and returns a test preparation strategy for Simulators with the given parameters.

 @param testLaunchConfiguration configuration used to launch test.
 @param workingDirectory directory used to prepare all bundles.
 @return a FBXCTestPreparationStrategy instance.
 */
+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration workingDirectory:(NSString *)workingDirectory;

#pragma mark Public Methods

/**
 Prepares FBTestRunnerConfiguration

 @param iosTarget iOS target used to prepare test
 @return A future that resolves with the a FBTestRunnerConfiguration configuration.
 */
- (FBFuture<FBTestRunnerConfiguration *> *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget;

@end

NS_ASSUME_NONNULL_END
