/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreSimulator/NSObject-Protocol.h>

@class NSObject, NSString, SimPasteboardItem;
@protocol NSSecureCoding;

@protocol SimPasteboardItemDataProvider <NSObject>
- (NSObject<NSSecureCoding> *)retrieveValueForSimPasteboardItem:(SimPasteboardItem *)arg1 type:(NSString *)arg2;
@end
