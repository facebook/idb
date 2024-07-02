/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

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
+ (FBFuture<FBTestRunnerConfiguration *> *)prepareConfigurationWithTarget:(id<FBiOSTarget, FBXCTestExtendedCommands>)target testLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration workingDirectory:(NSString *)workingDirectory codesign:(nullable FBCodesignProvider *)codesign;

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
+ (NSDictionary<NSString *, NSString *> *)launchEnvironmentWithHostApplication:(FBBundleDescriptor *)hostApplication hostApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)hostApplicationAdditionalEnvironment testBundle:(FBBundleDescriptor *)testBundle testConfigurationPath:(NSString *)testConfigurationPath frameworkSearchPaths:(NSArray<NSString *> *)frameworkSearchPaths;

#pragma mark Properties

/**
 Test session identifier
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 Test runner app used for testing
 */
@property (nonatomic, strong, readonly) FBBundleDescriptor *testRunner;

/**
  Launch arguments for test runner
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *launchArguments;

/**
 Launch environment variables for test runner
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *launchEnvironment;

/**
 Launch environment variables added to test target application
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *testedApplicationAdditionalEnvironment;

@property (nonatomic, strong, readonly) FBTestConfiguration *testConfiguration;

@end

NS_ASSUME_NONNULL_END
