/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class DTXConnection;
@class DTXTransport;
@protocol XCTestManager_DaemonConnectionInterface;
@protocol XCTestManager_IDEInterface;
@protocol FBControlCoreLogger;
@protocol XCTestDriverInterface;

NS_ASSUME_NONNULL_BEGIN

/**
 A Connection to a Test Daemon.
 */
@interface FBTestDaemonConnection : NSObject

/**
 Creates a Strategy for the provided Transport.

 @param transport the transport to connect with.
 @param interface the interface to delegate to.
 @param testBundleProxy the Bundle Proxy.
 @param queue the dispatch queue to serialize asynchronous events on.
 @param testRunnerPID the Process Identifier of the Test Runner.
 @param logger the logger to log to.
 @return a new Strategy
 */
+ (instancetype)withTransport:(DTXTransport *)transport interface:(id<XCTestManager_IDEInterface, NSObject>)interface testBundleProxy:(id<XCTestDriverInterface>)testBundleProxy testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Synchronously Connects the Daemon.

 @param timeout the time to wait for connection to appear.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Disconnects any active connection.
 */
- (void)disconnect;

/**
 Properties from the Constructor.
 */
@property (nonatomic, strong, readonly) DTXTransport *transport;
@property (nonatomic, weak, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<XCTestDriverInterface> testBundleProxy;
@property (nonatomic, assign, readonly) pid_t testRunnerPID;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

/**
 Properties populated during the connection.
 */
@property (nonatomic, assign, readonly) long long daemonProtocolVersion;
@property (nonatomic, nullable, strong, readonly) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (nonatomic, nullable, strong, readonly) DTXConnection *daemonConnection;
@property (nonatomic, nullable, strong, readonly) NSError *error;
@property (nonatomic, assign, readonly) BOOL connected;

@end

NS_ASSUME_NONNULL_END
