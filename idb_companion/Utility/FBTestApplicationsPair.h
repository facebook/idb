/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBInstalledApplication;

/**
 The Pair of Applications that are required for test execution.
 This may or may not be relevant, as decided by the FBXCTestDescriptor.
 */
@interface FBTestApplicationsPair : NSObject;

/**
 The Application Under Test.
 Only relevant for UI Tests.
 */
@property (nonatomic, strong, nullable, readonly) FBInstalledApplication *applicationUnderTest;

/**
 The Test Host App.
 The Application that Hosts a test bundle.
 Relevant for UI and Application Tests.
 */
@property (nonatomic, strong, nullable, readonly) FBInstalledApplication *testHostApp;

/**
 The Designated Initializer.
 */
- (instancetype)initWithApplicationUnderTest:(nullable FBInstalledApplication *)applicationUnderTest testHostApp:(nullable FBInstalledApplication *)testHostApp;

@end

NS_ASSUME_NONNULL_END
