/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestManagerContext;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol XCTestManager_IDEInterface;

/**
 A Connection to a Test Daemon.
 */
@interface FBTestDaemonConnection : NSObject

#pragma mark Initializers

/**
 Creates a Strategy for the provided Transport.

 @param context the Context of the Test Manager.
 @param target the iOS Target.
 @param interface the interface to delegate to.
 @param testHostApplication the launched test host application.
 @param requestQueue the dispatch queue to serialize asynchronous events on.
 @param logger the logger to log to.
 @return a new Strategy
 */
+ (FBFutureContext<NSNull *> *)daemonConnectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface testHostApplication:(id<FBLaunchedApplication>)testHostApplication requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger;


@end

NS_ASSUME_NONNULL_END
