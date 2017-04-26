/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBXCTestDestination;
@class FBXCTestLogger;
@class FBXCTestShimConfiguration;
@class FBXCTestContext;

@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

/**
 The Base Configuration for all tests.
 */
@interface FBXCTestConfiguration : NSObject

/**
 Creates and loads a configuration.

 @param arguments the Arguments to the fbxctest process
 @param environment environment additions for the process under test.
 @param workingDirectory the Working Directory to use.
 @param error an error out for any error that occurs
 @return a new test run configuration.
 */
+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory error:(NSError **)error;

/**
 Creates and loads a configuration.

 @param arguments the Arguments to the fbxctest process
 @param environment environment additions for the process under test.
 @param workingDirectory the Working Directory to use.
 @Param timeout the timeout of the test.
 @param error an error out for any error that occurs
 @return a new test run configuration.
 */
+ (nullable instancetype)configurationFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout error:(NSError **)error;

@property (nonatomic, copy, readonly) FBXCTestDestination *destination;
@property (nonatomic, copy, nullable, readonly) FBXCTestShimConfiguration *shims;

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *processUnderTestEnvironment;
@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) NSString *testBundlePath;
@property (nonatomic, copy, readonly) NSString *testType;

@property (nonatomic, assign, readonly) BOOL waitForDebugger;
@property (nonatomic, assign, readonly) NSTimeInterval testTimeout;


/**
 Locates the expected Installation Root.
 */
+ (nullable NSString *)fbxctestInstallationRoot;

/**
 Gets the Environment for a Subprocess.
 Will extract the environment variables from the appropriately prefixed environment variables.
 Will strip out environment variables that will confuse subprocesses if this class is called inside an 'xctest' environment.

 @param entries the entries to add in
 @return the subprocess environment
 */
- (NSDictionary<NSString *, NSString *> *)buildEnvironmentWithEntries:(NSDictionary<NSString *, NSString *> *)entries;

@end

/**
 A Test Configuration, specialized to the listing of Test Bundles.
 */
@interface FBListTestConfiguration : FBXCTestConfiguration

@end

/**
 A Test Configuration, specialized to running of Application Tests.
 */
@interface FBApplicationTestConfiguration : FBXCTestConfiguration

/**
 The Path to the Application Hosting the Test.
 */
@property (nonatomic, copy, readonly) NSString *runnerAppPath;

@end

/**
 A Test Configuration, specialized to the running of Logic Tests.
 */
@interface FBLogicTestConfiguration : FBXCTestConfiguration

/**
 The Filter for Logic Tests.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testFilter;

@end

NS_ASSUME_NONNULL_END
