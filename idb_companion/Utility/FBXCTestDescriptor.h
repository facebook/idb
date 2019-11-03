/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestApplicationsPair;

/**
 Serialization-independent protocol for describing how to start a test run, sent over the wire.
 */
@protocol FBXCTestRunRequest <NSObject>

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

@end

/**
 Value implementation of FBXCTestRunRequest
 */
@interface FBXCTestRunRequest : NSObject <FBXCTestRunRequest>

/**
 The Designated Initializer.
 */
- (instancetype)initWithLogicTest:(BOOL)logicTest uiTest:(BOOL)uiTest testBundleID:(NSString *)testBundleID appBundleID:(nullable NSString *)appBundleID testHostAppBundleID:(nullable NSString *)testHostAppBundleID environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip testTimeout:(NSNumber *)testTimeout;

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
- (FBFuture<NSNull *> *)setupWithRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target;

/**
 Creates test config from the thrift request and host applications.

 @param request the xctest run request
 @param testApps the materialized Applications that are used as a part of testing.
 */
- (FBTestLaunchConfiguration *)testConfigWithRunRequest:(id<FBXCTestRunRequest>)request testApps:(FBTestApplicationsPair *)testApps;

/**
 Obtains the Test Application Components for the provided target and request

 @param request the incoming request.
 @param target the target to obtain applications for.
 @return a Future wrapping the Application Pair.
 */
- (FBFuture<FBTestApplicationsPair *> *)testAppPairForRequest:(id<FBXCTestRunRequest>)request target:(id<FBiOSTarget>)target;

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
