/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

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
 @param queue the dispatch queue to serialize asynchronous events on.
 @param logger the logger to log to.
 @return a new Strategy
 */
+ (instancetype)connectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Lifecycle

/**
 Synchronously Connects the Daemon.

 @param timeout the time to wait for connection to appear.
 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestDaemonResult *)connectWithTimeout:(NSTimeInterval)timeout;

/**
 Notifies the Connection that the Test Plan has started.
 Test Events will be delivered asynchronously to the interface.

 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestDaemonResult *)notifyTestPlanStarted;

/**
 Notifies the Connection that the Test Plan has ended.
 Test Events will be delivered asynchronously to the interface.

 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestDaemonResult *)notifyTestPlanEnded;

/**
 Checks that a Result is available.
 */
- (nullable FBTestDaemonResult *)checkForResult;

/**
 Disconnects any active connection.

 @return a Result.
 */
- (FBTestDaemonResult *)disconnect;

#pragma mark Properties

/**
 Properties populated during the connection.
 */
@property (atomic, assign, readonly) long long daemonProtocolVersion;
@property (atomic, nullable, strong, readonly) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (atomic, nullable, strong, readonly) DTXConnection *daemonConnection;

@end

NS_ASSUME_NONNULL_END
