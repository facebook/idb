/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <AXRuntime/AXTraits.h>
#import <FBControlCore/FBControlCore.h>

@interface AXTraitsTest : XCTestCase
@end

@implementation AXTraitsTest

- (void)testMappingNames
{
  NSDictionary<NSNumber *, NSString *> *mapping = AXTraitToNameMap();
  XCTAssertEqualObjects(mapping[@(AXTraitLink)], @"Link");
  XCTAssertEqualObjects(mapping[@(AXTraitButton)], @"Button");
}

- (void)testEmptyTraitExtraction
{
  XCTAssertEqualObjects(AXExtractTraits(AXTraitNone), [NSSet setWithObject:@"None"]);
}

- (void)testSingleTraitExtraction
{
  XCTAssertEqualObjects(AXExtractTraits(AXTraitButton), [NSSet setWithObject:@"Button"]);
}

- (void)testUnknownTraitExtraction
{
  XCTAssertEqualObjects(AXExtractTraits((uint64)1 << 63), [NSSet setWithObject:@"Unknown"]);
}

- (void)testCombinedTraitExtraction
{
  NSSet *expectedSet = [NSSet setWithObjects:@"Button", @"Selected", nil];
  XCTAssertEqualObjects(AXExtractTraits(AXTraitButton | AXTraitSelected), expectedSet);
}

- (void)testCombinedTraitExtractionWithUnknownTrait
{
  NSSet *expectedSet = [NSSet setWithObjects:@"Button", @"Unknown", nil];
  XCTAssertEqualObjects(AXExtractTraits(AXTraitButton | (uint64)1 << 63), expectedSet);
}

@end
