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

@interface FBDiagnosticTests : FBControlCoreValueTestCase

@end

@implementation FBDiagnosticTests

- (NSString *)temporaryOutputFile
{
  return [[NSTemporaryDirectory() stringByAppendingPathComponent:@"FBDiagnosticTests"] stringByAppendingPathExtension:@"tempout"];
}

- (id)jsonFixture
{
  return  @{
    @"bing" : @"bong",
    @"animal" : @"cat",
    @"somes" : @[
      @1, @2, @3, @4, @"FOO BAR BAAAA"
    ],
  };
}

- (void)testValueSemantics
{
  NSArray *values = @[self.photoDiagnostic, self.simulatorSystemLog, self.treeJSONDiagnostic];
  [self assertEqualityOfCopy:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)assertWritesOutToFile:(FBDiagnostic *)diagnostic
{
  NSString *outFile = self.temporaryOutputFile;
  NSError *error = nil;
  BOOL success = [diagnostic writeOutToFilePath:outFile error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSData *readData = [[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updatePath:outFile]
    build]
    asData];
  XCTAssertEqualObjects(diagnostic.asData, readData);
}

- (void)testBuilderBuilds
{
  NSData *data = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[[[[FBDiagnosticBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:data]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"shortname");
  XCTAssertEqualObjects(diagnostic.fileType, @"filetype");
  XCTAssertEqualObjects(diagnostic.humanReadableName, @"human");
  XCTAssertEqualObjects(diagnostic.asData, data);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBuilderReplacesExistingProperties
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[[[[FBDiagnosticBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:firstData]
    build];

  NSData *secondData = [@"SOME NEW DATA" dataUsingEncoding:NSUTF8StringEncoding];

  diagnostic = [[[[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateShortName:@"newshortname"]
    updateFileType:@"newfiletype"]
    updateHumanReadableName:@"newhuman"]
    updateData:secondData]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"newshortname");
  XCTAssertEqualObjects(diagnostic.fileType, @"newfiletype");
  XCTAssertEqualObjects(diagnostic.humanReadableName, @"newhuman");
  XCTAssertEqualObjects(diagnostic.asData, secondData);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBuilderReplacesStringsAndData
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updateData:firstData]
    build];

  diagnostic = [[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateString:@"A String"]
    build];

  XCTAssertEqualObjects(diagnostic.asData, [@"A String" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(diagnostic.asString, @"A String");

  diagnostic = [[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateString:@"Not me ever"]
    updateData:[@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]]
    build];

  XCTAssertEqualObjects(diagnostic.asData, [@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(diagnostic.asString, @"I am now over here");
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testStringAccessorReadsFromFile
{
  NSString *logString = @"FOO BAR BAZ";
  NSString *logPath = self.temporaryOutputFile;
  [logString writeToFile:logString atomically:YES encoding:NSUTF8StringEncoding error:nil];

  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updatePath:logPath]
    build];

  XCTAssertEqualObjects(diagnostic.asString, diagnostic.asString);
}

- (void)testReadingPathWritesToFile
{
  NSString *logString = @"FOO BAR BAZ";

  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateString:logString]
    updateShortName:@"ballooon"]
    build];

  NSString *writeOutString = [NSString stringWithContentsOfFile:diagnostic.asPath usedEncoding:nil error:nil];

  XCTAssertEqualObjects(writeOutString, logString);
}

- (void)testInitializesDefaultsWhenPopulatingFromFile
{
  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updatePath:FBControlCoreFixtures.simulatorSystemLogPath]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"simulator_system");
  XCTAssertEqualObjects(diagnostic.fileType, @"log");
}

- (void)testDoesNotInitializeDefaultsWhenAlreadySpecified
{
  FBDiagnostic *diagnostic = [[[[[FBDiagnosticBuilder builder]
    updateShortName:@"bibble"]
    updateFileType:@"txt"]
    updatePath:FBControlCoreFixtures.simulatorSystemLogPath]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"bibble");
  XCTAssertEqualObjects(diagnostic.fileType, @"txt");
}

- (void)testUpdatingAFileBackedDiagnostic
{
  NSString *file = self.temporaryOutputFile;
  XCTAssertTrue([@"FIRST" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);

  FBDiagnostic *fileDiagnostic = [[[FBDiagnosticBuilder builder]
    updatePath:file]
    build];
  FBDiagnostic *memoryDiagnostic = [[[FBDiagnosticBuilder builderWithDiagnostic:fileDiagnostic]
    readIntoMemory]
    build];
  XCTAssertEqualObjects(@"FIRST", fileDiagnostic.asString);
  XCTAssertEqualObjects(@"FIRST", memoryDiagnostic.asString);

  XCTAssertTrue([@"SECOND" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]);
  XCTAssertEqualObjects(@"SECOND", fileDiagnostic.asString);
  XCTAssertEqualObjects(@"FIRST", memoryDiagnostic.asString);
}

- (void)testTextFileCoercions
{
  FBDiagnostic *diagnostic = self.simulatorSystemLog;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  XCTAssertTrue([diagnostic.asString containsString:@"layer position 375 667 bounds 0 0 750 1334"]);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testBinaryFileCoercions
{
  FBDiagnostic *diagnostic = self.photoDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asString);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertFalse(diagnostic.isSearchableAsText);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONNativeObjectCoercions
{
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"somelog"]
    updateJSON:self.jsonFixture]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects(diagnostic.asJSON, self.jsonFixture);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  XCTAssertTrue([diagnostic.asString containsString:@"FOO BAR BAAAA"]);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONDataCoercions
{
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.jsonFixture options:NSJSONWritingPrettyPrinted error:nil];
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"somelog"]
    updateData:jsonData]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects(diagnostic.asJSON, self.jsonFixture);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  XCTAssertTrue([diagnostic.asString containsString:@"FOO BAR BAAAA"]);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONFileCoercions
{
  FBDiagnostic *diagnostic = self.treeJSONDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects([[[diagnostic.asJSON objectForKey:@"value"] objectForKey:@"tree"] objectForKey:@"name"], @"SpringBoard");
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  XCTAssertTrue([diagnostic.asString containsString:@"Swipe down with three fingers to reveal the notification center"]);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONSerializableCoercions
{
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"process_info"]
    updateJSON:self.launchCtlProcess]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects([diagnostic.asJSON objectForKey:@"pid"] , @(NSProcessInfo.processInfo.processIdentifier));
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  XCTAssertTrue([diagnostic.asString containsString:[@(NSProcessInfo.processInfo.processIdentifier) stringValue]]);
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONFileWiring
{
  FBDiagnostic *localFile = self.treeJSONDiagnostic;
  FBDiagnostic *wireDiagnostic = [[[FBDiagnosticBuilder
    builderWithDiagnostic:localFile]
    readIntoMemory]
    build];

  id json = [wireDiagnostic jsonSerializableRepresentation];
  NSError *error = nil;
  FBDiagnostic *remoteDiagnostic = [FBDiagnostic inflateFromJSON:json error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(remoteDiagnostic);
  XCTAssertEqualObjects(localFile.shortName, remoteDiagnostic.shortName);
  XCTAssertTrue([remoteDiagnostic.asString containsString:@"Swipe down with three fingers to reveal the notification center"]);
}

- (void)testWritingToFile
{
  FBDiagnostic *diagnostic = self.treeJSONDiagnostic;
  FBDiagnostic *outDiagnostic = [[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    writeOutToFile]
    build];
  XCTAssertEqualObjects(diagnostic.asPath, outDiagnostic.asPath);
}

@end
