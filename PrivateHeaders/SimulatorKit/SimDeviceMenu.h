/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/NSMenu.h>

@class NSMutableDictionary, SimDeviceMenuItemPair, SimDeviceSet;
@protocol SimDeviceMenuDelegate;

/**
 Removed from SimulatorKit as of Xcode 27 (CoreSimulator 1155.4): the simulator hardware-menu model. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimDeviceMenu : NSMenu
{
  id<SimDeviceMenuDelegate> _simDeviceMenuDelegate;
  SimDeviceSet *_deviceSet;
  unsigned long long _regID;
  NSMutableDictionary *_menuItemPairForDeviceUDID;
  SimDeviceMenuItemPair *_selectedMenuItemPair;
}

@property (nonatomic, retain) SimDeviceMenuItemPair *selectedMenuItemPair;
@property (nonatomic, retain) NSMutableDictionary *menuItemPairForDeviceUDID;
@property (nonatomic, assign) unsigned long long regID; // @synthesize regID=_regID;
@property (nonatomic, retain) SimDeviceSet *deviceSet;
@property (nonatomic, weak) id<SimDeviceMenuDelegate> simDeviceMenuDelegate;

- (BOOL)selectDevice:(id)arg1;
- (void)clearSelectedDevice;
- (void)openDeviceManager:(id)arg1;
- (void)userSelected:(id)arg1;
- (void)refreshMenu;
- (id)initWithTitle:(id)arg1;

@end
