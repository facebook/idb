/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulatorPool.h>

@class FBProcessFetcher;

@interface FBSimulatorPool ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) NSMutableOrderedSet *allocatedUDIDs;
@property (nonatomic, strong, readonly) NSMutableDictionary *allocationOptions;

- (instancetype)initWithSet:(FBSimulatorSet *)set logger:(id<FBControlCoreLogger>)logger;

@end
