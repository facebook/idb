/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBInteraction.h>

@interface FBInteraction ()

/**
 The NSMutableArray<id<FBInteraction>> to chain together.
 */
@property (nonatomic, strong) NSMutableArray *interactions;

/**
 Chains an interaction using the provided block

 @param block the block to perform the interaction, returning error information in the failure case.
 */
- (instancetype)interact:(BOOL (^)(NSError **))block;

/**
 Fails the Interaction with the provided error.

 @param error the error to fail the interaction with.
 */
- (instancetype)failWith:(NSError *)error;

/**
 Passes the interaction.
 */
- (instancetype)succeed;

/**
 Takes an NSArray<id<FBInteraction>> and returns an id<FBInteracton>.
 Any failing interaction will terminate the chain.

 @param interactions the interactions to chain together.
 */
+ (id<FBInteraction>)chainInteractions:(NSArray *)interactions;

@end

/**
 Implementation of id<FBInteraction> using a block
 */
@interface FBInteraction_Block : NSObject<FBInteraction>

@property (nonatomic, copy) BOOL (^block)(NSError **error);

+ (id<FBInteraction>)interactionWithBlock:( BOOL(^)(NSError **error) )block;

@end
