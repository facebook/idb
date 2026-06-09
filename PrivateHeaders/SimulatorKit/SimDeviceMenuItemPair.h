/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMenuItem;

/**
 Removed from SimulatorKit as of Xcode 27 (CoreSimulator 1155.4): the simulator hardware-menu model. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimDeviceMenuItemPair : NSObject
{
  NSMenuItem *_primaryMenuItem;
  NSMenuItem *_alternateMenuItem;
}

@property (nonatomic, retain) NSMenuItem *alternateMenuItem;
@property (nonatomic, retain) NSMenuItem *primaryMenuItem;

@end
