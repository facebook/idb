/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
- (FBFuture<id> *)prepare:(id<FBControlCoreLogger>)logger;

/**
 Teardown the resource.

 @param context the context to use.
 @param logger the logger to use.
 @return context
 */
- (FBFuture<NSNull *> *)teardown:(id)context logger:(id<FBControlCoreLogger>)logger;

/**
 The Name of the Resource.
 */
@property (nonatomic, copy, readonly) NSString *contextName;

/**
 The amount of time to allow the resource to be held with no-one utilizing it.
 This is useful for ensuring that the same connection
 */
@property (nonatomic, copy, readonly) NSNumber *contextPoolTimeout;
/**
 Allows the context to be shared.
 */
@property (nonatomic, assign, readonly) BOOL isContextSharable;

@end

/**
 Manages an asynchronous context that can only be used by a single consumer
 */
@interface FBFutureContextManager<ContextType : id> : NSObject

#pragma mark Initializers.

/**
 The Designated Initializer.

 @param queue the queue to use.
 @param delegate the delegate to use.
 @param logger the logger to use.
 @return a new FBFutureContextManager Instance.
 */
+ (instancetype)managerWithQueue:(dispatch_queue_t)queue delegate:(id<FBFutureContextManagerDelegate>)delegate logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods.

/**
 Aquire the Resource.

 @param purpose the purpose for utilization.
 @return a context that is available at some point in the future.
 */
- (FBFutureContext<ContextType> *)utilizeWithPurpose:(NSString *)purpose;

/**
 Synchronously attempt to utilize the context.

 @param purpose the purpose for utilization.
 @param error an error out for any error that occurs.
 @return the context if one could be synchronously used.
 */
- (nullable ContextType)utilizeNowWithPurpose:(NSString *)purpose error:(NSError **)error;

/**
 Synchronously attempt to return the context.

 @param purpose the purpose for utilization.
 @param error an error out for any error that occurs.
 @return the context if one could be synchronously returned.
 */
- (BOOL)returnNowWithPurpose:(NSString *)purpose error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
