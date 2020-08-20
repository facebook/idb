/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBIDBTestOperation;
@class FBTemporaryDirectory;
@class FBTestApplicationsPair;
@class FBXCTestBundleStorage;

@protocol FBXCTestReporter;
@protocol FBControlCoreLogger;

/**
 Describes the necessary information to start a test run.
 */
@interface FBXCTestRunRequest : NSObject

#pragma mark Initializers

/**
 The Initializer for Logic Tests.

 @param testBundleID the bundle id of the test to run.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param collectCoverage will collect llvm coverage data
 @return an FBXCTestRunRequest instance.
 */
+ (instancetype)logicTestWithTestBundleID:(NSString *)testBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage;

/**
The Initializer for App Tests.

 @param testBundleID the bundle id of the test to run.
 @param appBundleID the bundle id of the application to inject the test bundle into.
 @param environment environment for the application test process.
 @param arguments arguments for the application test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param collectCoverage will collect llvm coverage data
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)applicationTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities collectCoverage:(BOOL)collectCoverage;

/**
The Initializer for UI Tests.

 @param testBundleID the bundle id of the test to run.
 @param appBundleID the bundle id of the application to automatie.
 @param testHostAppBundleID the bundle id of the application hosting the test bundle.
 @param environment environment for the logic test process.
 @param arguments arguments for the logic test process.
 @param testsToRun the tests to run.
 @param testsToSkip the tests to skip
 @param testTimeout the timeout for the entire execution, nil if no timeout should be applied.
 @param reportActivities if set activities and their data will be reported
 @param collectCoverage will collect llvm coverage data
 @return an FBXCTestRunRequest instance.
*/
+ (instancetype)uiTestWithTestBundleID:(NSString *)testBundleID appBundleID:(NSString *)appBundleID testHostAppBundleID:(NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout reportActivities:(BOOL)reportActivities  collectCoverage:(BOOL)collectCoverage;

#pragma mark Properties

/**
 YES if a logic test, NO otherwise
 */
@property (nonatomic, assign, readonly) BOOL isLogicTest;

/**
 YES if a UI Test, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL isUITest;

/**
 The Bundle ID of the Test bundle.
 */
@property (nonatomic, copy, readonly) NSString *testBundleID;

/**
 The Bundle ID of the Application to test in, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSString *appBundleID;

/**
 The Bundle ID of the Test Host, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSString *testHostAppBundleID;

/**
 The environment variables for the application, if relevant
 */
@property (nonatomic, copy, nullable, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 The arguments for the application, if relevant
 */
@property (nonatomic, copy, nullable, readonly) NSArray<NSString *> *arguments;

/**
 The set of tests to run, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSSet<NSString *> *testsToRun;

/**
 The set of tests to skip, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSSet<NSString *> *testsToSkip;

/**
 The timeout of the entire execution, if relevant.
 */
@property (nonatomic, copy, nullable, readonly) NSNumber *testTimeout;


/**
 If set activities and their data will be reported
 */
@property (nonatomic, assign, readonly) BOOL reportActivities;

/**
 If set llvm coverage data will be collected
 */
@property (nonatomic, assign, readonly) BOOL collectCoverage;

/**
 Starts the test operation.

 @param bundleStorage the bundle storage class to use.
 @param target the target to run against.
 @param reporter the reporter to report test results to.
 @param logger the logger to log to.
 @param temporaryDirectory the temporary directory to use.
 @return a future that resolves when the test operation starts.
 */
- (FBFuture<FBIDBTestOperation *> *)startWithBundleStorageManager:(FBXCTestBundleStorage *)bundleStorage target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory;

@end

/**
 A Protocol that describes a Test Bundle that is present on the host.
 This holds the notion of an 'installed' test for any given target.
 This knowledge is used to translate an incoming rpc requests into an internal FBTestLaunchConfiguration.
 */
@protocol FBXCTestDescriptor <NSObject>

#pragma mark Properties

/**
 The URL of the Test Bundle
 */
@property (nonatomic, strong, readonly) NSURL *url;

/**
 The name of the test bundle.
 */
@property (nonatomic, strong, readonly) NSString *name;

/**
 The bundle ID of the test bundle.
 */
@property (nonatomic, strong, readonly) NSString *testBundleID;

/**
 The supported architectures of the test bundle.
 */
@property (nonatomic, strong, readonly) NSSet<NSString *> *architectures;

/**
 The underlying test bundle.
 */
@property (nonatomic, strong, readonly) FBBundleDescriptor *testBundle;

#pragma mark Public Methods.

/**
 Perform any necessary setup before the test.

 @param request the incoming request.
 @param target the target to run against.
 @return a future that resolves when the test is setup.
 */
- (FBFuture<NSNull *> *)setupWithRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target;

/**
 Creates test config from the thrift request and host applications.

 @param request the xctest run request
 @param testApps the materialized Applications that are used as a part of testing.
 @param logger the logger to log to
 @return a test launch configuration.
 */
- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logger:(id<FBControlCoreLogger>)logger;

/**
 Obtains the Test Application Components for the provided target and request

 @param request the incoming request.
 @param target the target to obtain applications for.
 @return a Future wrapping the Application Pair.
 */
- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(FBXCTestRunRequest *)request target:(id<FBiOSTarget>)target;

@end

/**
 An XCTest Descriptor backed by execution using XCTestBootstrap.
 */
@interface FBXCTestBootstrapDescriptor : NSObject <FBXCTestDescriptor>


#pragma mark Public Methods

/**
 The Designated Initializer

 @param url the url of the test bundle.
 @param name the name of the test bundle.
 @param testBundle the bundle injected.
 @return a new FBXCTestDescriptor instance.
 */
- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBBundleDescriptor *)testBundle;

@end

/**
 An XCTest Descriptor backed by exectution using xcodebuild.
 */
@interface FBXCodebuildTestRunDescriptor : NSObject <FBXCTestDescriptor>

#pragma mark Properties

/**
 The app bundle into which the test bundle is injected
 */
@property (nonatomic, strong, readonly) FBBundleDescriptor *testHostBundle;

#pragma mark Public Methods

/**
 The Designated Initializer

 @param url the url of the test bundle.
 @param name the name of the test bundle.
 @param testBundle the bundle injected.
 @param testHostBundle the the bundle into which the test bundle is injected
 @return a new FBXCTestDescriptor instance.
 */
- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name testBundle:(FBBundleDescriptor *)testBundle testHostBundle:(FBBundleDescriptor *)testHostBundle;

@end

NS_ASSUME_NONNULL_END
