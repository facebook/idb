/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Queries for an iOS Target Set.
 */
@interface FBiOSTargetProvider : NSObject

/**
 Provide a target with a specified identifier.

 @param udid iOS Target identifier.
 @param targetSets the target sets to fetch from.
 @param warmUp if YES then additional steps may be taken to get the target in a "warmer" state for usage in the companion.
 @param logger the logger to use.
 @return A future wrapping the fetched target.
 */
+ (FBFuture<id<FBiOSTarget>> *)targetWithUDID:(NSString *)udid targetSets:(NSArray<id<FBiOSTargetSet>> *)targetSets warmUp:(BOOL)warmUp logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
