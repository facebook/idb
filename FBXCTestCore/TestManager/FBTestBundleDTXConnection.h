/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class TestManagerContext;
@protocol ControlCoreLogger;

/**
 Told what the test bundle and testmanagerd do over the connection. Called on arbitrary queues.
 */
@protocol FBTestBundleDTXConnectionDelegate <NSObject>

/**
 The test bundle opened its proxy channel.
 */
- (void)testBundleConnectionDidOpenProxyChannel;

/**
 testmanagerd answered the session request, with an error if it refused it.
 */
- (void)testBundleConnectionDidStartSessionWithError:(nullable NSError *)error;

/**
 The test bundle is ready to execute its test plan.
 */
- (void)testBundleConnectionBundleDidBecomeReady;

/**
 The test bundle cannot run: a protocol mismatch, or UI testing failing to initialize.
 */
- (void)testBundleConnectionBundleDidFailWithError:(nonnull NSError *)error;

/**
 The test bundle finished executing its test plan.
 */
- (void)testBundleConnectionDidFinishTestPlan;

/**
 The testmanagerd connection went away.
 */
- (void)testBundleConnectionDidDisconnect;

@end

/**
 The Objective-C core of a test-bundle connection: it owns the DTX transport and proxy channels, implements the private XCTest `_XCT_*` callbacks, and forwards everything else to the IDE-interface delegate. The Swift `TestBundleConnection` drives it step by step.
 */
@interface FBTestBundleDTXConnection : NSObject

#pragma mark Initializers

/**
 @param interface the `XCTestManager_IDEInterface` / `XCTMessagingChannel_RunnerToIDE` implementor that bundle and daemon callbacks are forwarded to. Typed as `id` to keep private XCTest protocols out of this header.
 @param delegate told of each step of the session.
 */
- (nonnull instancetype)initWithContext:(nonnull TestManagerContext *)context workQueue:(nonnull dispatch_queue_t)workQueue socket:(int)socket interface:(nonnull id)interface delegate:(nonnull id<FBTestBundleDTXConnectionDelegate>)delegate requestQueue:(nonnull dispatch_queue_t)requestQueue logger:(nonnull id<ControlCoreLogger>)logger;

#pragma mark Step-wise connection API

/**
 Wraps the testmanagerd socket in a DTX connection. Pair with `-disconnect`, which the caller owes
 once this has returned YES.
 */
- (BOOL)connectWithError:(NSError *_Nullable *_Nullable)error;

/**
 Suspends and cancels the connection established by `-connectWithError:`. Synchronous: the
 connection is down when this returns. Safe to call when nothing is connected.
 */
- (void)disconnect;

/**
 Listens for the test bundle's proxy channel and asks testmanagerd to start the session. The delegate
 is told when each has happened.
 */
- (void)setupAndStartSession;

/**
 Tells the test bundle to begin executing the test plan. Call once the delegate has been told the
 bundle is ready.
 */
- (void)startExecutingTestPlan;

@end
