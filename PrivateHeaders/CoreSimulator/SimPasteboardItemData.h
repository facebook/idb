/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSString;
@protocol NSSecureCoding;

@interface SimPasteboardItemData : NSObject
{
    NSString *_type;
    NSObject<NSSecureCoding> *_value;
}

@property (retain, nonatomic) NSObject<NSSecureCoding> *value;
@property (nonatomic, copy) NSString *type;

- (id)initWithType:(id)arg1 value:(id)arg2;

@end
