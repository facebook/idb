/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class DTXConnection;
@class DVTDevice;
@class FBTestBundleResult;
@class FBTestManagerContext;
@class XCTestBootstrapError;

@protocol XCTestDriverInterface;
@protocol XCTestManager_IDEInterface;

/**
 A Strategy for Connecting.
 */
@interface FBTestBundleConnection : NSObject

#pragma mark Initializers

/**
 Constructs a Test Bundle Connection.

 @param context the Context of the Test Manager.
 @param target the iOS Target.
 @param interface the interface to delegate to.
 @param requestQueue the queue for asynchronous deliver.
 @param logger the Logger to Log to.
 @return a new Bundle Connection instance.
 */
+ (instancetype)connectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Lifecycle

/**
 Asynchronously Connects the to the Bundle

 @return a Future that resolves when the Bundle Connection is established.
 */
- (FBFuture<FBTestBundleResult *> *)connect;

/**
 Starts the Test Plan.
 Test Events will be delivered asynchronously to the interface.

 @return a Future that resolves when the Test Plan has completed.
 */
- (FBFuture<FBTestBundleResult *> *)startTestPlan;

/**
 A future for the end of the test run.

 @return a Future that resolves when the Test Run has completed.
 */
- (FBFuture<FBTestBundleResult *> *)completeTestRun;

/**
 Disconnects any active connection.

 @return a Future that resolves when the connection has been disconnected.
 */
- (FBFuture *)disconnect;

@end

NS_ASSUME_NONNULL_END
