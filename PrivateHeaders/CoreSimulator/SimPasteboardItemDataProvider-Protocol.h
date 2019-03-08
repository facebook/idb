/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/NSObject-Protocol.h>

@class NSObject, NSString, SimPasteboardItem;
@protocol NSSecureCoding;

@protocol SimPasteboardItemDataProvider <NSObject>
- (NSObject<NSSecureCoding> *)retrieveValueForSimPasteboardItem:(SimPasteboardItem *)arg1 type:(NSString *)arg2;
@end
