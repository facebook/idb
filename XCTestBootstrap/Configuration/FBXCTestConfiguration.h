/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A String Enum for Test Types.
 */
typedef NSString *FBXCTestType NS_STRING_ENUM;

/**
 An UITest.
 */
extern FBXCTestType const FBXCTestTypeUITest;

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

@class FBCodeCoverageConfiguration;
@class FBXCTestDestination;
@class FBXCTestShimConfiguration;

/**
 The Base Configuration for all tests.
 */
@interface FBXCTestConfiguration : NSObject <NSCopying>

/**
 The Default Initializer.
 This should not be called directly.
 */
- (instancetype)initWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout;

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
 The supported architectures of the test bundle.
 */
@property (nonatomic, strong, readonly, nonnull) NSSet<NSString *> *architectures;

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath runnerAppPath:(nullable NSString *)runnerAppPath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout architectures:(nonnull NSSet<NSString *> *)architectures;

@property (nonatomic, copy, readonly) NSString *runnerAppPath;

@end

/**
 A Test Configuration, specialized in running of Tests.
 */
@interface FBTestManagerTestConfiguration : FBXCTestConfiguration

/**
 The Path to the Application Hosting the Test.
 */
@property (nonatomic, copy, readonly) NSString *runnerAppPath;

/**
 The Path to the test target Application.
 */
@property (nonatomic, copy, readonly, nullable) NSString *testTargetAppPath;

/**
 The test filter for which test to run.
 Format: <testClass>/<testMethod>
 */
@property (nonatomic, copy, readonly, nullable) NSString *testFilter;

/**
 The path of log file that we dump all os_log to.
 (os_log means Apple's unified logging system (https://developer.apple.com/documentation/os/logging),
 we use this name to avoid confusing between various logging systems)
 */
@property (nonatomic, copy, readonly, nullable) NSString *osLogPath;

/**
 The path of video recording file that record the whole test run.
 */
@property (nonatomic, copy, readonly, nullable) NSString *videoRecordingPath;

/**
 A list of test artifcats filename globs (see https://en.wikipedia.org/wiki/Glob_(programming) ) that
 any files in app's container folder matching them will be copied out to a temporary path before
 simulator is cleaned up.
 */
@property (nonatomic, copy, readonly, nullable) NSArray<NSString *> *testArtifactsFilenameGlobs;

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout runnerAppPath:(NSString *)runnerAppPath testTargetAppPath:(nullable NSString *)testTargetAppPath testFilter:(nullable NSString *)testFilter videoRecordingPath:(nullable NSString *)videoRecordingPath testArtifactsFilenameGlobs:(nullable NSArray<NSString *> *)testArtifactsFilenameGlobs osLogPath:(nullable NSString *)osLogPath;

@end

typedef NS_OPTIONS(NSUInteger, FBLogicTestMirrorLogs) {
    /* Does not mirror logs */
    FBLogicTestMirrorNoLogs = 0,
    /* Mirrors logs to files */
    FBLogicTestMirrorFileLogs = 1 << 0,
    /* Mirrors logs to logger */
    FBLogicTestMirrorLogger = 1 << 1,
};

/**
 A Test Configuration, specialized to the running of Logic Tests.
 */
@interface FBLogicTestConfiguration : FBXCTestConfiguration

/**
 The Filter for Logic Tests.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testFilter;

/**
 How the logic test logs will be mirrored
 */
@property (nonatomic, readonly) FBLogicTestMirrorLogs mirroring;

/**
 The configuration for code coverage collection
*/
@property (nonatomic, nullable, retain, readonly) FBCodeCoverageConfiguration *coverageConfiguration;

/**
 The path to the test bundle binary
*/
@property (nonatomic, nullable, copy, readonly) NSString *binaryPath;

/**
 The Directory to use for storing logs generated during the execution of the test run.
 */
@property (nonatomic, nullable, copy, readonly) NSString *logDirectoryPath;

/**
 The supported architectures of the test bundle.
 */
@property (nonatomic, strong, readonly) NSSet<NSString *> *architectures;

/**
 The Designated Initializer.
 */
+ (instancetype)configurationWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory testBundlePath:(NSString *)testBundlePath waitForDebugger:(BOOL)waitForDebugger timeout:(NSTimeInterval)timeout testFilter:(nullable NSString *)testFilter mirroring:(FBLogicTestMirrorLogs)mirroring coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration binaryPath:(nullable NSString *)binaryPath logDirectoryPath:(nullable NSString *)logDirectoryPath architectures:(nonnull NSSet<NSString *> *)architectures;

@end

NS_ASSUME_NONNULL_END
