/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction.h"

@interface FBSimulatorInteraction ()

@property (nonatomic, strong) FBSimulator *simulator;
@property (nonatomic, strong) NSMutableArray *interactions;

+ (id<FBSimulatorInteraction>)chainInteractions:(NSArray *)interactions;

@end

@interface FBSimulatorInteraction_Block : NSObject<FBSimulatorInteraction>

@property (nonatomic, copy) BOOL (^block)(NSError **error);

+ (id<FBSimulatorInteraction>)interactionWithBlock:( BOOL(^)(NSError **error) )block;

@end
