/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
