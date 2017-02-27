/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/NSSecureCoding-Protocol.h>

@class NSData;

@interface SimPasteboardItemWrappedData : NSObject <NSSecureCoding>
{
    NSData *_wrappedData;
}

+ (BOOL)supportsSecureCoding;
@property (retain, nonatomic) NSData *wrappedData;

- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (id)initWithData:(id)arg1;

@end
