/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMenuItem;

@interface SimDeviceMenuItemPair : NSObject
{
  NSMenuItem *_primaryMenuItem;
  NSMenuItem *_alternateMenuItem;
}

@property (nonatomic, retain) NSMenuItem *alternateMenuItem;
@property (nonatomic, retain) NSMenuItem *primaryMenuItem;

@end
