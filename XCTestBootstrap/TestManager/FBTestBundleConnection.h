/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBTestManagerContext;

@protocol XCTestManager_IDEInterface;
@protocol XCTMessagingChannel_RunnerToIDE;

/**
 A Strategy for Connecting.
 */
@interface FBTestBundleConnection : NSObject

#pragma mark Initializers

/**
 Constructs a Test Bundle Connection and runs the test plan to completion

 @param context the Context of the Test Manager.
 @param target the iOS Target.
 @param interface the interface to delegate to.
 @param testHostApplication the hosting
 @param requestQueue the queue for asynchronous deliver.
 @param logger the Logger to Log to.
 @return a Future that resolves successfully when the test plan has completed.
 */
+ (nonnull FBFuture<NSNull *> *)connectAndRunBundleToCompletionWithContext:(nonnull FBTestManagerContext *)context target:(nonnull id<FBiOSTarget, FBXCTestExtendedCommands, FBApplicationCommands>)target interface:(nonnull id<XCTestManager_IDEInterface, XCTMessagingChannel_RunnerToIDE, NSObject>)interface testHostApplication:(nonnull id<FBLaunchedApplication>)testHostApplication requestQueue:(nonnull dispatch_queue_t)requestQueue logger:(nonnull id<FBControlCoreLogger>)logger;

@end
