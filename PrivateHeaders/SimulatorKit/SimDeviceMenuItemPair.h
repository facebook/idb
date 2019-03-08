/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSObject.h>

@class NSMenuItem;

@interface SimDeviceMenuItemPair : NSObject
{
    NSMenuItem *_primaryMenuItem;
    NSMenuItem *_alternateMenuItem;
}

@property (retain, nonatomic) NSMenuItem *alternateMenuItem;
@property (retain, nonatomic) NSMenuItem *primaryMenuItem;


@end

