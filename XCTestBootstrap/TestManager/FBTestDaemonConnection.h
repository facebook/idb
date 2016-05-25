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
@class DVTDevice;
@protocol XCTestManager_DaemonConnectionInterface;
@protocol XCTestManager_IDEInterface;
@protocol FBControlCoreLogger;
@protocol XCTestDriverInterface;

/**
 An Enumeration of Mutually-Exclusive Test Daemon States.
 */
typedef NS_ENUM(NSUInteger, FBTestDaemonConnectionState) {
  FBTestDaemonConnectionStateNotConnected = 0,
  FBTestDaemonConnectionStateConnecting = 1,
  FBTestDaemonConnectionStateReadyToExecuteTestPlan = 2,
  FBTestDaemonConnectionStateRunningTestPlan = 3,
  FBTestDaemonConnectionStateEndedTestPlan = 4,
  FBTestDaemonConnectionStateFinishedSuccessfully = 5,
  FBTestDaemonConnectionStateFinishedInError = 6,
};

NS_ASSUME_NONNULL_BEGIN

/**
 A Connection to a Test Daemon.
 */
@interface FBTestDaemonConnection : NSObject

/**
 Creates a Strategy for the provided Transport.

 @param device the transport to connect to.
 @param interface the interface to delegate to.
 @param queue the dispatch queue to serialize asynchronous events on.
 @param testRunnerPID the Process Identifier of the Test Runner.
 @param logger the logger to log to.
 @return a new Strategy
 */
+ (instancetype)withDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface testRunnerPID:(pid_t)testRunnerPID queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

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
 Notifies the Connection that the Test Plan has started.
 Test Events will be delivered asynchronously to the interface.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)notifyTestPlanStartedWithError:(NSError **)error;

/**
 Notifies the Connection that the Test Plan has ended.
 Test Events will be delivered asynchronously to the interface.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)notifyTestPlanEndedWithError:(NSError **)error;

/**
 Properties from the Constructor.
 */
@property (nonatomic, strong, readonly) DVTDevice *device;
@property (nonatomic, weak, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, assign, readonly) pid_t testRunnerPID;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

/**
 Properties populated during the connection.
 */
@property (atomic, assign, readonly) long long daemonProtocolVersion;
@property (atomic, nullable, strong, readonly) id<XCTestManager_DaemonConnectionInterface> daemonProxy;
@property (atomic, nullable, strong, readonly) DTXConnection *daemonConnection;
@property (atomic, assign, readonly) FBTestDaemonConnectionState state;

@end

NS_ASSUME_NONNULL_END
