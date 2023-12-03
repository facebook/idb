/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBTestConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 Context for FBTestManagerAPIMediator.
 */
@interface FBTestManagerContext : NSObject <NSCopying>

/**
 Constructor for the Test Manager Context.

 @param sessionIdentifier a session identifier of test that should be started
 @param timeout the maximum amount of time permitted for the test execution to finish.
 @param testHostLaunchConfiguration the process id of the Test Host Process. This is the process into which the Test Bundle is injected.
 @param testedApplicationAdditionalEnvironment Additional environment for the app-under-test.
 @return a new FBTestManagerContext instance.
 */
- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier timeout:(NSTimeInterval)timeout testHostLaunchConfiguration:(FBApplicationLaunchConfiguration *)testHostLaunchConfiguration  testedApplicationAdditionalEnvironment:(nullable NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment testConfiguration:(FBTestConfiguration *)testConfiguration;

/**
 A session identifier of test that should be started
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 The maximum amount of time permitted for the test execution to finish
 */
@property (nonatomic, assign, readonly) NSTimeInterval timeout;

/**
 The launch configuration for the test host.
 */
@property (nonatomic, strong, readonly) FBApplicationLaunchConfiguration *testHostLaunchConfiguration;
/**
 Additional environment for the app-under-test.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSString *> *testedApplicationAdditionalEnvironment;

@property (nonatomic, strong, readonly) FBTestConfiguration *testConfiguration;

@end

NS_ASSUME_NONNULL_END
