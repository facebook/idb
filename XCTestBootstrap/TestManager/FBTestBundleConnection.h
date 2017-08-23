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
@class FBTestBundleResult;
@class FBTestManagerContext;
@class XCTestBootstrapError;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol XCTestDriverInterface;
@protocol XCTestManager_IDEInterface;

/**
 A Strategy for Connecting.
 */
@interface FBTestBundleConnection : NSObject

#pragma mark Initializers

/**
 Constructs a Test Bundle Connection.

 @param context the Context of the Test Manager.
 @param target the iOS Target.
 @param interface the interface to delegate to.
 @param requestQueue the queue for asynchronous deliver.
 @param logger the Logger to Log to.
 @return a new Bundle Connection instance.
 */
+ (instancetype)connectionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target interface:(id<XCTestManager_IDEInterface, NSObject>)interface requestQueue:(dispatch_queue_t)requestQueue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Lifecycle

/**
 Synchonously Connects the to the Bundle

 @param timeout the amount of time to wait for the connection to be established.
 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestBundleResult *)connectWithTimeout:(NSTimeInterval)timeout;

/**
 Starts the Test Plan.
 Test Events will be delivered asynchronously to the interface.

 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestBundleResult *)startTestPlan;

/**
 Checks that a Result is available.

 @return a Result if unsuccessful, nil otherwise.
 */
- (nullable FBTestBundleResult *)checkForResult;

/**
 Disconnects any active connection.

 @return a Result.
 */
- (FBTestBundleResult *)disconnect;

@end

NS_ASSUME_NONNULL_END
