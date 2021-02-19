/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Context for FBTestManagerAPIMediator.
 */
@interface FBTestManagerContext : NSObject <NSCopying>

/**
 Constructor for the Test Manager Context.

 @param testRunnerPID the process id of the Test Host Process. This is the process into which the Test Bundle is injected.
 @param testRunnerBundleID the Bundle ID of the Test Host Process. This is the process into which the Test Bundle is injected.
 @param sessionIdentifier a session identifier of test that should be started
 @param testedApplicationAdditionalEnvironment Additional environment for the app-under-test.
 @return a new FBTestManagerContext instance.
 */
- (instancetype)initWithTestRunnerPID:(pid_t)testRunnerPID testRunnerBundleID:(NSString *)testRunnerBundleID sessionIdentifier:(NSUUID *)sessionIdentifier testedApplicationAdditionalEnvironment:(nullable NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment;

/**
 The process id of the Test Host Process. This is the process into which the Test Bundle is injected.
 */
@property (nonatomic, assign, readonly) pid_t testRunnerPID;

/**
 The Bundle ID of the Test Host Process. This is the process into which the Test Bundle is injected
 */
@property (nonatomic, copy, readonly) NSString *testRunnerBundleID;

/**
 A session identifier of test that should be started
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 Additional environment for the app-under-test.
 */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSString *> *testedApplicationAdditionalEnvironment;

@end

NS_ASSUME_NONNULL_END
