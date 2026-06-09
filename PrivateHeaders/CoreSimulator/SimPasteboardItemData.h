/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSString;
@protocol NSSecureCoding;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimPasteboardItemData : NSObject
{
  NSString *_type;
  NSObject<NSSecureCoding> *_value;
}

@property (nonatomic, retain) NSObject<NSSecureCoding> *value;
@property (nonatomic, copy) NSString *type;

- (id)initWithType:(id)arg1 value:(id)arg2;

@end
