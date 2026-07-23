/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBTestManagerContext;

/**
 The Objective-C core of a test-bundle connection: it owns the DTX transport and proxy channels, implements the private XCTest `_XCT_*` callbacks, and forwards everything else to the IDE-interface delegate. The Swift `FBTestBundleConnection` drives it step by step.
 */
@interface FBTestBundleDTXConnection : NSObject

#pragma mark Initializers

/**
 Constructs a Test Bundle Connection that a caller drives step by step.

 @param interface the IDE-interface delegate (an `XCTestManager_IDEInterface` / `XCTMessagingChannel_RunnerToIDE` implementor) that test bundle and daemon callbacks are forwarded to. Typed as `id` so this header stays free of private XCTest protocols.
 */
- (nonnull instancetype)initWithContext:(nonnull FBTestManagerContext *)context target:(nonnull id<FBiOSTarget>)target socket:(int)socket interface:(nonnull id)interface requestQueue:(nonnull dispatch_queue_t)requestQueue logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Step-wise connection API

/**
 Wraps the testmanagerd socket in a DTX connection. The returned context keeps the connection alive for the body and tears it down (suspend + cancel) when the scope exits.
 */
- (nonnull FBFutureContext<FBTestBundleDTXConnection *> *)connect;

/**
 Establishes the test-bundle proxy channel and starts the testmanagerd session, each with its own internal readiness timeout. Resolves when both have completed.
 */
- (nonnull FBFuture<NSNull *> *)setupAndStartSession;

/**
 Resolves when the test bundle reports it is ready (bounded by an internal timeout), or fails if the bundle reports a protocol mismatch / initialization error.
 */
- (nonnull FBFuture<NSNull *> *)waitForBundleReady;

/**
 Tells the test bundle to begin executing the test plan. Call after `waitForBundleReady`.
 */
- (void)startExecutingTestPlan;

/**
 Resolves when the test bundle disconnects.
 */
- (nonnull FBFuture<NSNull *> *)waitForBundleDisconnected;

/**
 Whether `_XCT_didFinishExecutingTestPlan` has been received.
 */
@property (nonatomic, readonly, assign) BOOL testPlanCompleted;

@end
