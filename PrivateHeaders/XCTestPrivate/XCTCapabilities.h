/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@interface XCTCapabilities : NSObject <NSSecureCoding>
{
    NSDictionary *_capabilitiesDictionary;
}

+ (id)emptyCapabilities;
+ (_Bool)supportsSecureCoding;

@property(readonly, copy) NSDictionary *capabilitiesDictionary; // @synthesize capabilitiesDictionary=_capabilitiesDictionary;
- (_Bool)hasCapability:(id)arg1;
- (unsigned long long)versionForCapability:(id)arg1;
- (unsigned long long)hash;
- (_Bool)isEqual:(id)arg1;
- (id)description;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
@property(readonly, copy) NSDictionary *dictionaryRepresentation;
- (id)initWithDictionary:(id)arg1;

@end
