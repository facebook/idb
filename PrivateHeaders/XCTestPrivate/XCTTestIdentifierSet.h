/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTTestIdentifier;

@interface XCTTestIdentifierSet : NSObject <NSCopying, NSFastEnumeration, NSSecureCoding>
{
}

+ (_Bool)supportsSecureCoding;
+ (id)allocWithZone:(struct _NSZone *)arg1;
+ (id)emptyTestIdentifierSet;
- (Class)classForCoder;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (unsigned long long)countByEnumeratingWithState:(id)arg1 objects:(id *)arg2 count:(unsigned long long)arg3;
- (_Bool)isEqual:(id)arg1;
- (id)description;
- (_Bool)containsTestIdentifier:(id)arg1;
@property(readonly) unsigned long long count;
- (id)init;
- (id)initWithTestIdentifiers:(const id *)arg1 count:(unsigned long long)arg2;
- (id)initWithSet:(id)arg1;
- (id)initWithArray:(id)arg1;
- (id)initWithTestIdentifier:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;
@property(readonly) NSDictionary *testIdentifiersGroupedByFirstComponentIdentifier;
- (id)builder;
- (id)setByAddingTestIdentifiersFromSet:(id)arg1;
@property(readonly) XCTTestIdentifier *anyTestIdentifier;

@end

