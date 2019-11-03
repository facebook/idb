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
@class FBTestDaemonResult;
@class FBTestManagerContext;
@class XCTestBootstrapError;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol XCTestDriverInterface;
@protocol XCTestManager_DaemonConnectionInterface;
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
 @param requestQueue the dispatch queue to serialize asynchronous events on.
 @param logger the logger to log to.
 @return a new Strategy
 */
+ (instancetype)connectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Lifecycle

/**
 Asynchronously Connects the Daemon.

 @return a Future that resolves when the Daemon Connection is established.
 */
- (FBFuture<FBTestDaemonResult *> *)connect;

/**
 Notifies the Connection that the Test Plan has started.
 Test Events will be delivered asynchronously to the interface.

 @return a Future that resolves when the notification is successful.
 */
- (FBFuture<FBTestDaemonResult *> *)notifyTestPlanStarted;

/**
 Notifies the Connection that the Test Plan has ended.
 Test Events will be delivered asynchronously to the interface.

 @return a Future that resolves when the notification is successful.
 */
- (FBFuture<FBTestDaemonResult *> *)notifyTestPlanEnded;

/**
 Checks that a Result is available.
 
 @return a Future that resolves when the daemon has completed it's work.
 */
- (FBFuture<FBTestDaemonResult *> *)completed;

/**
 Disconnects any active connection.

 @return a Future that resolves when the disconnection has completed.
 */
- (FBTestDaemonResult *)disconnect;

@end

NS_ASSUME_NONNULL_END
