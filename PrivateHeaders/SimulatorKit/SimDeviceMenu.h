/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/NSMenu.h>

@class NSMutableDictionary, SimDeviceMenuItemPair, SimDeviceSet;
@protocol SimDeviceMenuDelegate;

@interface SimDeviceMenu : NSMenu
{
    id <SimDeviceMenuDelegate> _simDeviceMenuDelegate;
    SimDeviceSet *_deviceSet;
    unsigned long long _regID;
    NSMutableDictionary *_menuItemPairForDeviceUDID;
    SimDeviceMenuItemPair *_selectedMenuItemPair;
}

@property (retain, nonatomic) SimDeviceMenuItemPair *selectedMenuItemPair;
@property (retain, nonatomic) NSMutableDictionary *menuItemPairForDeviceUDID;
@property(nonatomic, assign) unsigned long long regID; // @synthesize regID=_regID;
@property (retain, nonatomic) SimDeviceSet *deviceSet;
@property (nonatomic, assign) id <SimDeviceMenuDelegate> simDeviceMenuDelegate;

- (BOOL)selectDevice:(id)arg1;
- (void)clearSelectedDevice;
- (void)openDeviceManager:(id)arg1;
- (void)userSelected:(id)arg1;
- (void)refreshMenu;
- (id)initWithTitle:(id)arg1;

@end

