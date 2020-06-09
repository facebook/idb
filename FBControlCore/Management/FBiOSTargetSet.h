/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSTargetStateUpdate.h>

/**
 Delegate that informs of updates regarding the set of iOS Targets.
 */
@protocol FBiOSTargetSetDelegate

/**
 Called every time an iOS Target's state is updated.
 This includes state changes such a Simulator booting or a device connecting.

 @param update the state update to report.
 */
- (void)targetDidUpdate:(FBiOSTargetStateUpdate *)update;

@end

/**
 Common properties of of iOS Target Sets, shared by Simulator & Device Sets.
 */
@protocol FBiOSTargetSet <NSObject>

/**
 The Delegate of the Target Set.
 Used to report updates out.
 */
@property (nonatomic, weak, readwrite) id<FBiOSTargetSetDelegate> delegate;

/**
 Obtains all current targets infos within a set.
 */
@property (nonatomic, copy, readonly) NSArray<id<FBiOSTargetInfo>> *allTargetInfos;

@end
