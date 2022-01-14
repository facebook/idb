/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@interface XCTTestIdentifier : NSObject <NSCopying, NSSecureCoding>
{
}

+ (_Bool)supportsSecureCoding;
+ (id)allocWithZone:(struct _NSZone *)arg1;
+ (id)bundleIdentifier;
+ (id)identifierForClass:(Class)arg1;
+ (id)leafIdentifierWithComponents:(id)arg1;
+ (id)containerIdentifierWithComponents:(id)arg1;
+ (id)containerIdentifierWithComponent:(id)arg1;
- (Class)classForCoder;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
@property(readonly) unsigned long long options;
- (id)componentAtIndex:(unsigned long long)arg1;
@property(readonly) unsigned long long componentCount;
@property(readonly) NSArray *components;
- (id)initWithComponents:(id)arg1 options:(unsigned long long)arg2;
- (id)initWithStringRepresentation:(id)arg1 preserveModulePrefix:(_Bool)arg2;
- (id)initWithStringRepresentation:(id)arg1;
- (id)initWithClassName:(id)arg1;
- (id)initWithClassName:(id)arg1 methodName:(id)arg2;
- (id)initWithClassAndMethodComponents:(id)arg1;
- (id)initWithComponents:(id)arg1 isContainer:(_Bool)arg2;
- (id)copyWithZone:(struct _NSZone *)arg1;
@property(readonly) XCTTestIdentifier *swiftMethodCounterpart;
@property(readonly) XCTTestIdentifier *firstComponentIdentifier;
@property(readonly) XCTTestIdentifier *parentIdentifier;
- (id)_identifierString;
@property(readonly) NSString *identifierString;
@property(readonly) NSString *displayName;
@property(readonly) NSString *lastComponentDisplayName;
@property(readonly) NSString *lastComponent;
@property(readonly) NSString *firstComponent;
@property(readonly) _Bool representsBundle;
@property(readonly) _Bool isLeaf;
@property(readonly) _Bool isContainer;
- (unsigned long long)hash;
- (_Bool)isEqual:(id)arg1;
- (id)debugDescription;
- (id)description;
@property(readonly) _Bool isSwiftMethod;
@property(readonly) _Bool usesClassAndMethodSemantics;

@end

