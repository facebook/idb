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

/** Substitutes a runtime for tests, or restores the live runtime when passed nil. */
+ (void)setRuntimeForTesting:(nullable id<FBAXRuntime>)runtime;
/** Substitutes initialization without sharing the production dispatch-once state. */
+ (void)setRuntimeFactoryForTesting:(nullable FBAXRuntimeFactory)factory;

@end

NS_ASSUME_NONNULL_END
