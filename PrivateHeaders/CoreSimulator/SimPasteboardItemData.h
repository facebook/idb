/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
