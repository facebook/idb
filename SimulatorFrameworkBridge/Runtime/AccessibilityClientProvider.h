/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "AccessibilityClient.h"

NS_ASSUME_NONNULL_BEGIN

/** Reuses the process-wide runtime binding and contains initialization exceptions. */
@interface FBAXClientProvider : NSObject

+ (void)prepare;
+ (nullable FBAXClient *)clientWithError:(NSError *_Nullable *_Nullable)error;

/**
 Whether a read of this process went unanswered and has not been seen to finish since. The application keeps
 working on a read after the reader stops waiting, so anything sent meanwhile queues behind it.
 */
+ (BOOL)hasUnansweredReadForProcessIdentifier:(pid_t)processIdentifier;
+ (void)setHasUnansweredRead:(BOOL)unanswered forProcessIdentifier:(pid_t)processIdentifier;

/** Substitutes a runtime for tests, or restores the live runtime when passed nil. Forgets unanswered reads. */
+ (void)setRuntimeForTesting:(nullable id<FBAXRuntime>)runtime;
/** Substitutes initialization without sharing the production dispatch-once state. */
+ (void)setRuntimeFactoryForTesting:(nullable FBAXRuntimeFactory)factory;

@end

NS_ASSUME_NONNULL_END
