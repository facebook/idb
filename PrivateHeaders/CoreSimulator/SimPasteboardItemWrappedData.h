/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
