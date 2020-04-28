/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestBootstrap/FBProductBundle.h>

@class FBTestConfiguration;

/**
 Represents test bundle (aka .xctest)
 */
@interface FBTestBundle : FBProductBundle

/**
 The current test configuration file for test bundle
 */
@property (nonatomic, strong, readonly) FBTestConfiguration *configuration;

@end

/**
 Prepares FBTestBundle by:
 - coping it to workingDirectory, if set
 - creating and saving test configuration file if sessionIdentifier is set
 - codesigning bundle with codesigner, if set
 - loading bundle information from Info.plist file
 */
@interface FBTestBundleBuilder : FBProductBundleBuilder

/**
 @param sessionIdentifier session identifier for test configuration
 @return builder
 */
- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier;

/**
 @param shouldInitializeForUITesting determines whether should initialize for UITesting
 @return builder
 */
- (instancetype)withUITesting:(BOOL)shouldInitializeForUITesting;

/**
 Adds tests to run.

 @param testsToRun tests to run
 @return builder
 */
- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun;

/**
 Adds tests to skip.

 @param testsToSkip tests to skip
 @return builder
 */
- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip;

/**
 Adds bundle ID of to the target application for UI tests.

 @param targetApplicationBundleID bundle ID of to the target application
 @return builder
 */
- (instancetype)withTargetApplicationBundleID:(NSString *)targetApplicationBundleID;

/**
 Adds path to the target application for UI tests.

 @param targetApplicationPath path to the target application
 @return builder
 */
- (instancetype)withTargetApplicationPath:(NSString *)targetApplicationPath;

/**
 Adds path to automation framework.

 @param automationFrameworkPath path to automation framework
 @return builder
 */
- (instancetype)withAutomationFrameworkPath:(NSString *)automationFrameworkPath;

/**
 Controls whether activities are reported

 @param reportActivities if set activity data will be reported
 @return builder
*/
- (instancetype)withReportActivities:(BOOL)reportActivities;

/**
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return prepared test bundle if the operation succeeds, otherwise nil.
 */
- (FBTestBundle *)buildWithError:(NSError **)error;

@end
