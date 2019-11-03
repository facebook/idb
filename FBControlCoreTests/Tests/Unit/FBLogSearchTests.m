/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testFindsWithinText
{
  FBLogSearch *searcher = [FBLogSearch withText:@"Hellop\nBye\nHellooeeeeee" predicate:[FBLogSearchPredicate substrings:@[
    @"Hello",
  ]]];
  XCTAssertEqualObjects(searcher.firstMatch, @"Hello");
  XCTAssertEqualObjects(searcher.matchingLines, (@[@"Hellop", @"Hellooeeeeee"]));
}

- (void)testFindsMatchInFileDiagnostic
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"Installed apps did change",
    @"Couldn't find the digitizer HID service, this is probably bad"
  ]]];
  XCTAssertEqualObjects(searcher.firstMatch, @"Installed apps did change");
  XCTAssertEqualObjects(searcher.firstMatchingLine, @"Mar  7 16:50:18 some-hostname SpringBoard[24911]: Installed apps did change.");
}

- (void)testFailsToFindAbsentSubstrings
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"LOLIDK1",
    @"LOLIDK2"
  ]]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

- (void)testFindsMultipleSubstrings
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate substrings:@[
    @"Cloud Resources scheduler activated"
  ]]];
  XCTAssertEqual(searcher.allMatches.count, 9u);
  XCTAssertEqual(searcher.matchingLines.count, 9u);
}

- (void)testFindsMatchInFileRegex
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate regex:
    @"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"
  ]];
  XCTAssertEqualObjects(searcher.firstMatch, @"layer position 375 667 bounds 0 0 750 133");
  XCTAssertEqualObjects(searcher.firstMatchingLine, @"Mar  7 16:50:18 some-hostname backboardd[24912]: layer position 375 667 bounds 0 0 750 1334");
}

- (void)testFailsToFindAbsentRegex
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.simulatorSystemLog predicate:[FBLogSearchPredicate regex:
    @"layer position \\D+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"
  ]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

- (void)testDoesNotFindInBinaryDiagnostics
{
  FBLogSearch *searcher = [FBDiagnosticLogSearch withDiagnostic:self.photoDiagnostic predicate:[FBLogSearchPredicate substrings:@[
    @"LOLIDK",
    @"Installed apps did change",
    @"Couldn't find the digitizer HID service, this is probably bad"
  ]]];
  XCTAssertNil(searcher.firstMatch);
  XCTAssertNil(searcher.firstMatchingLine);
}

- (void)testCompilesSubstringMatchingArgumentsForLogCommand
{
  NSArray<FBLogSearchPredicate *> *predicates = @[
    [FBLogSearchPredicate substrings:@[@"foo", @"bar"]],
    [FBLogSearchPredicate substrings:@[@"baz"]],
    [FBLogSearchPredicate regex:@"ban(t|s)"],
  ];
  NSError *error = nil;
  NSString *string = [FBLogSearchPredicate logAgumentsFromPredicates:predicates error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(string, @"eventMessage contains 'foo' || eventMessage contains 'bar' || eventMessage contains 'baz' || eventMessage MATCHES 'ban(t|s)'");
}

@end

@interface FBBatchLogSearcherTests : FBControlCoreValueTestCase

@end

@implementation FBBatchLogSearcherTests

- (NSDictionary *)complexMapping
{
  return @{
    @"simulator_system" : @[
      [FBLogSearchPredicate substrings:@[@"Springboard", @"SpringBoard", @"IOHIDSession"]],
      [FBLogSearchPredicate regex:@"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"],
      [FBLogSearchPredicate substrings:@[@"ADDING REMOTE com.apple.Maps"]],
      [FBLogSearchPredicate regex:@"(ANIMPOSSIBLE|REGEAAAAAAAAA)"],
    ],
    @"tree" : @[
      [FBLogSearchPredicate substrings:@[@"Springboard", @"SpringBoard", @"IOHIDSession"]],
      [FBLogSearchPredicate regex:@"(ANIMPOSSIBLE|REGEAAAAAAAAA)"],
    ],
    @"photo0" : @[
      [FBLogSearchPredicate substrings:@[@"BAAAAAAAA"]],
    ]
  };
}

- (NSDictionary *)searchAllMapping
{
  return @{@"" : @[
    [FBLogSearchPredicate substrings:@[@"Springboard", @"SpringBoard", @"IOHIDSession"]],
    [FBLogSearchPredicate regex:@"layer position \\d+ \\d+ bounds \\d+ \\d+ \\d+ \\d+"],
    [FBLogSearchPredicate substrings:@[@"ADDING REMOTE com.apple.Maps"]],
    [FBLogSearchPredicate regex:@"(ANIMPOSSIBLE|REGEAAAAAAAAA)"],
    [FBLogSearchPredicate substrings:@[@"111", @"222"]],
  ]};
}

- (NSArray *)diagnostics
{
  return @[
    self.simulatorSystemLog,
    self.treeJSONDiagnostic,
    self.photoDiagnostic,
  ];
}

- (NSArray *)batches
{
  return @[
    [FBBatchLogSearch searchWithMapping:self.complexMapping options:FBBatchLogSearchOptionsFirstMatch since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.complexMapping options:FBBatchLogSearchOptionsFullLines since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.complexMapping options:(FBBatchLogSearchOptionsFirstMatch |FBBatchLogSearchOptionsFullLines) since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.complexMapping options:0 since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:FBBatchLogSearchOptionsFirstMatch since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:FBBatchLogSearchOptionsFullLines since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:(FBBatchLogSearchOptionsFirstMatch |FBBatchLogSearchOptionsFullLines) since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:0 since:nil error:nil],
    [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:0 since:[NSDate dateWithTimeIntervalSince1970:1231] error:nil],
  ];
}

- (void)testValueSemanticsOfSearch
{
  NSArray *batches = self.batches;
  [self assertEqualityOfCopy:batches];
  [self assertJSONSerialization:batches];
  [self assertJSONDeserialization:batches];
}

- (void)testValueSemanticsOfResult
{
  for (FBBatchLogSearch *batch in self.batches) {
    FBBatchLogSearchResult *result = [batch searchDiagnostics:self.diagnostics];
    [self assertEqualityOfCopy:@[result]];
    [self assertJSONSerialization:@[result]];
    [self assertJSONDeserialization:@[result]];
  }
}

- (void)testBatchSearchFindsLinesAcrossMultipleDiagnostics
{
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch searchWithMapping:self.complexMapping options:FBBatchLogSearchOptionsFullLines since:nil error:nil];
  NSDictionary *results = [[batchSearch searchDiagnostics:self.diagnostics] mapping];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 99u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);

  XCTAssertEqualObjects(results[@"simulator_system"][0], @"Mar  7 16:50:18 some-hostname backboardd[24912]: ____IOHIDSessionScheduleAsync_block_invoke: thread_id=0x700000323000");
  XCTAssertEqualObjects(results[@"simulator_system"][97], @"Mar  7 16:50:18 some-hostname backboardd[24912]: layer position 375 667 bounds 0 0 750 1334");
  XCTAssertEqualObjects(results[@"simulator_system"][98], @"Mar  7 16:50:21 some-hostname SpringBoard[24911]: ADDING REMOTE com.apple.Maps, <BBRemoteDataProvider 0x7fca290e3fc0; com.apple.Maps>");
}

- (void)testBatchSearchFindsFirstLineAcrossMultipleDiagnostics
{
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch searchWithMapping:self.complexMapping options:(FBBatchLogSearchOptionsFirstMatch | FBBatchLogSearchOptionsFullLines) since:nil error:nil];
  NSDictionary *results = [[batchSearch searchDiagnostics:self.diagnostics] mapping];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 3u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);

  XCTAssertEqualObjects(results[@"simulator_system"][0], @"Mar  7 16:50:18 some-hostname backboardd[24912]: ____IOHIDSessionScheduleAsync_block_invoke: thread_id=0x700000323000");
}

- (void)testBatchSearchFindsExtractsAcrossMultipleDiagnostics
{
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch searchWithMapping:self.complexMapping options:0 since:nil error:nil];
  NSDictionary *results = [[batchSearch searchDiagnostics:self.diagnostics] mapping];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 99u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);

  XCTAssertEqualObjects(results[@"simulator_system"][0], @"IOHIDSession");
  XCTAssertEqualObjects(results[@"simulator_system"][97], @"layer position 375 667 bounds 0 0 750 133");
  XCTAssertEqualObjects(results[@"simulator_system"][98], @"ADDING REMOTE com.apple.Maps");
}

- (void)testSearchAllFindsAcrossAllDiagnostics
{
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:FBBatchLogSearchOptionsFullLines since:nil error:nil];
  NSDictionary *results = [[batchSearch searchDiagnostics:self.diagnostics] mapping];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 100u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);
}

- (void)testSearchAllFindsFirstAcrossAllDiagnostics
{
  FBBatchLogSearch *batchSearch = [FBBatchLogSearch searchWithMapping:self.searchAllMapping options:FBBatchLogSearchOptionsFirstMatch since:nil error:nil];
  NSDictionary *results = [[batchSearch searchDiagnostics:self.diagnostics] mapping];
  XCTAssertNotNil(results);
  XCTAssertEqual([results[@"simulator_system"] count], 4u);
  XCTAssertEqual([results[@"tree"] count], 1u);
  XCTAssertEqual([results[@"photo0"] count], 0u);
}

@end
