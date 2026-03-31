/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBBundleDescriptor;
@class FBTestBundle;
@class FBTestConfiguration;

@protocol FBiOSTarget;
@protocol FBXCTestExtendedCommands;
/**
 A Configuration Value for the Test Runner.
 */
@interface FBTestRunnerConfiguration : NSObject <NSCopying>

#pragma mark Initializers

/**
 Prepares a Test Runner Configuration.

 @param target the target to run against.
 @param testLaunchConfiguration the configuration for the test launch
 @param workingDirectory the working directory to use.
 @param codesign if set this will be used for checking code signatures.
 @return a Future that will resolve with the Test Runner configuration.
 */
+ (nonnull FBFuture<FBTestRunnerConfiguration *> *)prepareConfigurationWithTarget:(nonnull id<FBiOSTarget, FBXCTestExtendedCommands>)target testLaunchConfiguration:(nonnull FBTestLaunchConfiguration *)testLaunchConfiguration workingDirectory:(nonnull NSString *)workingDirectory codesign:(nullable FBCodesignProvider *)codesign;

#pragma mark Public

/**
 Construct the environment variables that are used by the runner app.

 @param hostApplication the application bundle.
 @param hostApplicationAdditionalEnvironment additional environment variables that are passed into the runner app.
 @param testBundle the test bundle.
 @param testConfigurationPath FBTestConfiguration object.
 @param frameworkSearchPaths the list of search paths to add in the launch.
 @return a new environment dictionary.
 */
+ (nonnull NSDictionary<NSString *, NSString *> *)launchEnvironmentWithHostApplication:(nonnull FBBundleDescriptor *)hostApplication hostApplicationAdditionalEnvironment:(nonnull NSDictionary<NSString *, NSString *> *)hostApplicationAdditionalEnvironment testBundle:(nonnull FBBundleDescriptor *)testBundle testConfigurationPath:(nonnull NSString *)testConfigurationPath frameworkSearchPaths:(nonnull NSArray<NSString *> *)frameworkSearchPaths;

#pragma mark Properties

/**
 Test session identifier
 */
@property (nonnull, nonatomic, readonly, copy) NSUUID *sessionIdentifier;

/**
 Test runner app used for testing
 */
@property (nonnull, nonatomic, readonly, strong) FBBundleDescriptor *testRunner;

/**
  Launch arguments for test runner
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<NSString *> *launchArguments;

/**
 Launch environment variables for test runner
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *launchEnvironment;

/**
 Launch environment variables added to test target application
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *testedApplicationAdditionalEnvironment;

@property (nonnull, nonatomic, readonly, strong) FBTestConfiguration *testConfiguration;

@end
