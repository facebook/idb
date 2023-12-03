/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBIDBAppHostedTestConfiguration;
@class FBTestApplicationsPair;
@class FBXCTestRunRequest;

@protocol FBControlCoreLogger;

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
 @param logDirectoryPath the path to the log directory, if present.
 @param queue the queue to be used for async operations
 @return a Future wrapping the app-hosted test configuration if constructed successfully or an error.
 */
- (FBFuture<FBIDBAppHostedTestConfiguration *> *)testConfigWithRunRequest:(FBXCTestRunRequest *)request testApps:(FBTestApplicationsPair *)testApps logDirectoryPath:(nullable NSString *)logDirectoryPath logger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue;

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
