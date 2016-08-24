/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 Context for the Test Manager.
 */
@interface FBTestManagerContext : NSObject <NSCopying>

/**
 Constructor for the Test Manager Context.

 @param testRunnerPID a process id of the Test Host Process. This is the process into which the Test Bundle is injected.
 @param testRunnerBundleID the Bundle ID of the Test Host Process. This is the process into which the Test Bundle is injected.
 @param sessionIdentifier a session identifier of test that should be started
 @return a new FBTestManagerContext instance.
 */
+ (instancetype)contextWithTestRunnerPID:(pid_t)testRunnerPID testRunnerBundleID:(NSString *)testRunnerBundleID sessionIdentifier:(NSUUID *)sessionIdentifier;

@property (nonatomic, assign, readonly) pid_t testRunnerPID;
@property (nonatomic, copy, readonly) NSString *testRunnerBundleID;
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

@end
