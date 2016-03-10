/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"
#import "FBControlCoreValueTestCase.h"

@interface FBLogSearchTests : FBControlCoreValueTestCase

@end

@implementation FBLogSearchTests

- (void)testValueSemantics
{
  NSArray *values = @[
    [FBLogSearchPredicate substrings:@[@"Springboard", @"IOHIDSession", @"rect"]],
    [FBLogSearchPredicate regex:@"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testFindsMatchInFileDiagnostic
{
  FBLogSearch *searcher = [FBLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"Installed apps did change",
    @"Couldn't find the digitizer HID service, this is probably bad"
  ]]];
  XCTAssertEqualObjects(searcher.firstMatch, @"Installed apps did change");
  XCTAssertEqualObjects(searcher.firstMatchingLine, @"Mar  7 16:50:18 some-hostname SpringBoard[24911]: Installed apps did change.");
}

- (void)testFailsToFindAbsentSubstrings
{
  FBLogSearch *searcher = [FBLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"LOLIDK1",
    @"LOLIDK2"
  ]]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

- (void)testFindsMatchInFileRegex
{
  FBLogSearch *searcher = [FBLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate regex:
    @"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"
  ]];
  XCTAssertEqualObjects(searcher.firstMatch, @"layer position 375 667 bounds 0 0 750 1334");
  XCTAssertEqualObjects(searcher.firstMatchingLine, @"Mar  7 16:50:18 some-hostname backboardd[24912]: layer position 375 667 bounds 0 0 750 1334");
}

- (void)testFailsToFindAbsentRegex
{
  FBLogSearch *searcher = [FBLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate regex:
    @"layer position \\D+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"
  ]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

- (void)testDoesNotFindInBinaryDiagnostics
{
  FBLogSearch *searcher = [FBLogSearch withDiagnostic:self.photoDiagnostic predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"Installed apps did change",
    @"Couldn't find the digitizer HID service, this is probably bad"
  ]]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

@end

@interface FBBatchLogSearcherTests : XCTestCase

@end

@implementation FBBatchLogSearcherTests

- (void)testBatchSearchFindsAcrossMultipleDiagnostics
{
  NSDictionary *mapping = @{
    @[@"simulator_system", @"tree"] : @[
      [FBLogSearchPredicate substrings:@[@"Springboard", @"IOHIDSession", @"rect"]],
      [FBLogSearchPredicate regex:@"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"]
    ],
    @[@"simulator_system"] : @[
      [FBLogSearchPredicate substrings:@[@"ADDING REMOTE com.apple.Maps"]],
    ],
    @[@"tree"] : @[
      [FBLogSearchPredicate regex:@"(ANIMPOSSIBLE|REGEAAAAAAAAA)"],
    ],
    @[@"photo0"] : @[
      [FBLogSearchPredicate substrings:@[@"111", @"222"]],
    ]
  };
  NSError *error = nil;
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch withMapping:mapping error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(batchSearch);
  NSDictionary *results = [batchSearch search:@[
    self.simulatorSystemLog,
    self.treeJSONDiagnostic,
    self.photoDiagnostic
  ]];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 3u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);
}

- (void)testSearchAllFindsAcrossAllDiagnostics
{
  NSDictionary *mapping = @{@[] : @[
    [FBLogSearchPredicate substrings:@[@"Springboard", @"IOHIDSession", @"rect"]],
    [FBLogSearchPredicate regex:@"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"],
    [FBLogSearchPredicate substrings:@[@"ADDING REMOTE com.apple.Maps"]],
    [FBLogSearchPredicate regex:@"(ANIMPOSSIBLE|REGEAAAAAAAAA)"],
    [FBLogSearchPredicate substrings:@[@"111", @"222"]],
  ]};
  NSError *error = nil;
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch withMapping:mapping error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(batchSearch);
  NSDictionary *results = [batchSearch search:@[
    self.simulatorSystemLog,
    self.treeJSONDiagnostic,
    self.photoDiagnostic
  ]];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 4u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);
}

@end
