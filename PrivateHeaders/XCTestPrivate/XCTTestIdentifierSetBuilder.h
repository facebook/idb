/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMutableSet, XCTTestIdentifierSet;

@interface XCTTestIdentifierSetBuilder : NSObject <NSCopying>
{
    NSMutableSet *_testIdentifiers;
}

- (id)copyWithZone:(struct _NSZone *)arg1;
- (void)addTestIdentifierWithLegacyStringRepresentation:(id)arg1 includingSwiftCounterpart:(_Bool)arg2;
- (void)minusBuilder:(id)arg1;
- (void)minusSet:(id)arg1;
- (void)unionBuilder:(id)arg1;
- (void)unionSet:(id)arg1;
- (void)removeAllTestIdentifiers;
- (void)removeTestIdentifier:(id)arg1;
- (void)addTestIdentifier:(id)arg1;
- (_Bool)containsTestIdentifier:(id)arg1;
@property(readonly) XCTTestIdentifierSet *testIdentifierSet;
@property(readonly) unsigned long long count;
- (id)initWithTestIdentifierSet:(id)arg1;
- (id)initWithSet:(id)arg1;
- (id)initWithArray:(id)arg1;
- (id)initWithTestIdentifier:(id)arg1;
- (id)init;

@end

