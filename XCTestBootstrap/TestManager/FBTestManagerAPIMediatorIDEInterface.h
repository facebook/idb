/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBTestManagerAPIMediator;
@class FBTestManagerContext;

@protocol FBControlCoreLogger;
@protocol FBLaunchedApplication;
@protocol FBXCTestExtendedCommands;
@protocol FBXCTestReporter;
@protocol FBiOSTarget;

NS_ASSUME_NONNULL_BEGIN

/**
 The Objective-C delegate implementing the private XCTest `XCTestManager_IDEInterface` /
 `XCTMessagingChannel_RunnerToIDE` callback surface that the test runner and `testmanagerd`
 communicate with over the DTX channel.

 This object intentionally stays in Objective-C because it depends on private XCTest types
 (`XCTTestIdentifier`, `XCTIssue`, `XCActivityRecord`, `DTXRemoteInvocationReceipt`, …). It owns
 no `FBFuture`-based application logic: the orchestration and all application lifecycle operations
 live in the Swift `FBTestManagerAPIMediator`, to which this delegate forwards process launch and
 termination requests.
 */
@interface FBTestManagerAPIMediatorIDEInterface : NSObject

#pragma mark Initializers

/**
 Constructs the IDE interface delegate.

 @param mediator the Swift mediator that owns orchestration and application lifecycle.
 @param context the Context of the Test Manager.
 @param reporter the delegate to report test progress to.
 @param logger the logger to log events to.
 */
- (instancetype)initWithMediator:(FBTestManagerAPIMediator *)mediator context:(FBTestManagerContext *)context reporter:(id<FBXCTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public

/**
 Connects to the test bundle and runs the test plan to completion, using the receiver as the
 IDE interface that the test bundle and daemon communicate with.

 @param target the target.
 @param testHostApplication the launched test host application.
 @param requestQueue the queue for asynchronous delivery.
 @return a Future that resolves when the test plan has completed.
 */
- (FBFuture<NSNull *> *)runBundleToCompletionWithTarget:(id<FBiOSTarget, FBXCTestExtendedCommands>)target testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue;

@end

NS_ASSUME_NONNULL_END
