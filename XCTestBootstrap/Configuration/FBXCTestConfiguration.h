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

NS_ASSUME_NONNULL_BEGIN

/**
 A String Enum for Test Types.
 */
typedef NSString *FBXCTestType NS_STRING_ENUM;

/**
 An Application Test.
 */
#define FBXCTestTypeApplicationTestValue @"application-test"
extern FBXCTestType const FBXCTestTypeApplicationTest;

/**
 A Logic Test.
 */
extern FBXCTestType const FBXCTestTypeLogicTest;

/**
 The Listing of Testing of tests in a bundle.
 */
extern FBXCTestType const FBXCTestTypeListTest;

@class FBXCTestDestination;
@class FBXCTestShimConfiguration;

/**
 The Base Configuration for all tests.
 */
@interface FBXCTestConfiguration : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

/**
 The Default Initializer.
 This should not be called directly.
 */
- (instancetype)initWithDestination:(FBXCTestDestination *)destination shims:(nullable FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(nullable NSString *)runnerAppPath testFilter:(nullable NSString *)testFilter;

/**
 The Destination Runtime to run against.
 */
@property (nonatomic, copy, readonly) FBXCTestDestination *destination;

/**
 The Shims to use for relevant test runs.
 */
@property (nonatomic, copy, nullable, readonly) FBXCTestShimConfiguration *shims;

/**
 The Environment Variables for the Process-Under-Test that is launched.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *processUnderTestEnvironment;

/**
 The Directory to use for files required during the execution of the test run.
 */
@property (nonatomic, copy, readonly) NSString *workingDirectory;

/**
 The Test Bundle to Execute.
 */
@property (nonatomic, copy, readonly) NSString *testBundlePath;

/**
 The Type of the Test Bundle.
 */
@property (nonatomic, copy, readonly) FBXCTestType testType;

/**
 YES if the test execution should pause on launch, waiting for a debugger to attach.
 NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL waitForDebugger;

/**
 The Timeout to wait for the test execution to finish.
 */
@property (nonatomic, assign, readonly) NSTimeInterval testTimeout;

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

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout;

@end

/**
 A Test Configuration, specialized to running of Application Tests.
 */
@interface FBApplicationTestConfiguration : FBXCTestConfiguration

/**
 The Path to the Application Hosting the Test.
 */
@property (nonatomic, copy, readonly) NSString *runnerAppPath;

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath;

@end

/**
 A Test Configuration, specialized to the running of Logic Tests.
 */
@interface FBLogicTestConfiguration : FBXCTestConfiguration

/**
 The Filter for Logic Tests.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testFilter;

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithDestination:(FBXCTestDestination *)destination shims:(FBXCTestShimConfiguration *)shims environment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(nullable NSString *)testFilter;

@end

NS_ASSUME_NONNULL_END
