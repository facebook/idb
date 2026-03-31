/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBFuture<T>;
@class FBFutureContext<T>;

@protocol FBControlCoreLogger;

/**
 The Delegate for a Context Manager
 */
@protocol FBFutureContextManagerDelegate <NSObject>

/**
 Prepare the Resource.

 @param logger the logger to use.
 @return a Future that resolves with the prepared context.
 */
- (nonnull FBFuture<id> *)prepare:(nonnull id<FBControlCoreLogger>)logger;

/**
 Teardown the resource.

 @param context the context to use.
 @param logger the logger to use.
 @return context
 */
- (nonnull FBFuture<NSNull *> *)teardown:(nonnull id)context logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 The Name of the Resource.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *contextName;

/**
 The amount of time to allow the resource to be held with no-one utilizing it.
 This is useful for ensuring that the same connection
 */
@property (nullable, nonatomic, readonly, copy) NSNumber *contextPoolTimeout;
/**
 Allows the context to be shared.
 */
@property (nonatomic, readonly, assign) BOOL isContextSharable;

@end

/**
 Manages an asynchronous context that can only be used by a single consumer
 */
@interface FBFutureContextManager <ContextType : id> : NSObject

#pragma mark Initializers.

/**
 The Designated Initializer.

 @param queue the queue to use.
 @param delegate the delegate to use.
 @param logger the logger to use.
 @return a new FBFutureContextManager Instance.
 */
+ (nonnull instancetype)managerWithQueue:(nonnull dispatch_queue_t)queue delegate:(nonnull id<FBFutureContextManagerDelegate>)delegate logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Public Methods.

/**
 Aquire the Resource.

 @param purpose the purpose for utilization.
 @return a context that is available at some point in the future.
 */
- (nonnull FBFutureContext<ContextType> *)utilizeWithPurpose:(nonnull NSString *)purpose;

/**
 Synchronously attempt to utilize the context.

 @param purpose the purpose for utilization.
 @param error an error out for any error that occurs.
 @return the context if one could be synchronously used.
 */
- (nullable ContextType)utilizeNowWithPurpose:(nonnull NSString *)purpose error:(NSError * _Nullable * _Nullable)error;

/**
 Synchronously attempt to return the context.

 @param purpose the purpose for utilization.
 @param error an error out for any error that occurs.
 @return the context if one could be synchronously returned.
 */
- (BOOL)returnNowWithPurpose:(nonnull NSString *)purpose error:(NSError * _Nullable * _Nullable)error;

@end
