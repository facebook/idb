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
@protocol FBControlCoreLogger;
@protocol XCTestDriverInterface;
@protocol XCTestManager_IDEInterface;

/**
 An Enumeration of mutually exclusive states of the connection
 */
typedef NS_ENUM(NSUInteger, FBTestBundleConnectionState) {
  FBTestBundleConnectionStateNotConnected = 0,
  FBTestBundleConnectionStateConnecting = 1,
  FBTestBundleConnectionStateTestBundleReady = 2,
  FBTestBundleConnectionStateAwaitingStartOfTestPlan = 3,
  FBTestBundleConnectionStateRunningTestPlan = 4,
  FBTestBundleConnectionStateEndedTestPlan = 5,
  FBTestBundleConnectionStateFinishedSuccessfully = 6,
  FBTestBundleConnectionStateFinishedInError = 7,
};

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for Connecting.
 */
@interface FBTestBundleConnection : NSObject

/**
 Constructs a Test Bundle Connection.

 @param device the device to connect to.
 @param interface the interface to delegate to.
 @param sessionIdentifier the Session Identifier.
 @param queue the queue for asynchronous deliver.
 @param logger the Logger to Log to.
 @return a new Bundle Connection instance.
 */
+ (instancetype)withDevice:(DVTDevice *)device interface:(id<XCTestManager_IDEInterface, NSObject>)interface sessionIdentifier:(NSUUID *)sessionIdentifier queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Synchonously Connects the to the Bundle

 @param timeout the time to wait for the bundle to connect
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Starts the Test Plan.
 Test Events will be delivered asynchronously to the interface.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startTestPlanWithError:(NSError **)error;

/**
 Disconnects any active connection.
 */
- (void)disconnect;

/**
 Properties set through the Constructor.
 */
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, weak, readonly) id<XCTestManager_IDEInterface, NSObject> interface;
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) DVTDevice *device;

/**
 Properties set from a connection.
 */
@property (atomic, assign, readonly) FBTestBundleConnectionState state;
@property (atomic, assign, readonly) long long testBundleProtocolVersion;
@property (atomic, nullable, strong, readonly) id<XCTestDriverInterface> testBundleProxy;
@property (atomic, nullable, strong, readonly) DTXConnection *testBundleConnection;

@end

NS_ASSUME_NONNULL_END
