/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSTargetStateUpdate.h>


/**
 Delegate to inform of updates regarding the set of targets
 */
@protocol FBiOSTargetSetDelegate

/**
 called everytime an iOS Target has an update.
 i.e. simulator boots or device connects/disconnects
 */
- (void)targetDidUpdate:(FBiOSTargetStateUpdate *)update;

@end

/**
 Common Properties of Devices sets & Simulators sets.
 */
@protocol FBiOSTargetSet <NSObject>

@property (nonatomic, weak, readwrite) id<FBiOSTargetSetDelegate> delegate;

@end
