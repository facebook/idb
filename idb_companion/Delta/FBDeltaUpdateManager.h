/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A session of delta updates
 */
@interface FBDeltaUpdateSession <DeltaType : id> : NSObject

#pragma mark Properties

/**
 The Unique Identifier of the Session.
 */
@property (nonatomic, copy, readonly) NSString *identifier;

#pragma mark Public Methods

/**
 Obtains the delta update, getting the incremental output.
 */
- (FBFuture<DeltaType> *)obtainUpdates;

/**
 Terminates the session, getting the remaining incremental output.
 */
- (FBFuture<DeltaType> *)terminate;

@end

/**
 A manager of delta updates
 */
@interface FBDeltaUpdateManager <DeltaType : id, OperationType: id<FBiOSTargetContinuation>, ParamType: id> : NSObject

/**
 The Designated Initializer.

 @param target the target to run against.
 @param name the name of the manager
 @param expiration the expiration, if automatically evicting. If nil there is no expiration
 @param capacity the maximum number of concurrent sessions. if nil, then is unbounded.
 @param logger the logger to log to.
 @param create a mapping of params to operation.
 @param delta a mapping of operation to delta. Will be invoked repeatedly to map an operation to it's incremental output. The done param specifies the current state, and can be set to terminate a session.
 @return the delta update manager.
 */
+ (instancetype)managerWithTarget:(id<FBiOSTarget>)target name:(NSString *)name expiration:(nullable NSNumber *)expiration capacity:(nullable NSNumber *)capacity logger:(id<FBControlCoreLogger>)logger create:(FBFuture<OperationType> * (^)(ParamType))create delta:(FBFuture<DeltaType> * (^)(OperationType operation, NSString *identifier, BOOL *done))delta;

#pragma mark Public

/**
 Gets the session

 @param identifier the identifier of the session. If nil, assumes that there is a single active session
 @return a future wrapping the session.
 */
- (FBFuture<FBDeltaUpdateSession<DeltaType> *> *)sessionWithIdentifier:(nullable NSString *)identifier;

/**
 Starts a session.

 @param params the params to pass to the operation.
 @return a future that resolves with operation
 */
- (FBFuture<FBDeltaUpdateSession<DeltaType> *> *)startSession:(ParamType)params;

@end

NS_ASSUME_NONNULL_END
