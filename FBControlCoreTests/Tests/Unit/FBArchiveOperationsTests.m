/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreLoggerDouble.h"

@interface FBArchiveOperationsTests : XCTestCase
{
  id<FBControlCoreLogger> _logger;
  NSString *_tempDirectory;
}
@end

@implementation FBArchiveOperationsTests

- (void)setUp
{
  [super setUp];
  _logger = [[FBControlCoreLoggerDouble alloc] init];
  _tempDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  [NSFileManager.defaultManager createDirectoryAtPath:_tempDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown
{
  [NSFileManager.defaultManager removeItemAtPath:_tempDirectory error:nil];
  [super tearDown];
}

#pragma mark - commandToExtractArchiveAtPath

- (void)testCommandToExtractArchive_NoOverrideMTime_NoDebug
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractArchiveAtPath:@"/tmp/archive.tar.gz"
    toPath:@"/tmp/output"
    overrideModificationTime:NO
    debugLogging:NO];

  XCTAssertEqual(command.count, 5u, @"Command should have 5 elements");
  XCTAssertEqualObjects(command[0], @"-zxp", @"Flags should be -zxp without m or v");
  XCTAssertEqualObjects(command[1], @"-C", @"Second element should be -C");
  XCTAssertEqualObjects(command[2], @"/tmp/output", @"Third element should be the extract path");
  XCTAssertEqualObjects(command[3], @"-f", @"Fourth element should be -f");
  XCTAssertEqualObjects(command[4], @"/tmp/archive.tar.gz", @"Fifth element should be the archive path");
}

- (void)testCommandToExtractArchive_WithOverrideMTime_NoDebug
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractArchiveAtPath:@"/tmp/archive.tar.gz"
    toPath:@"/tmp/output"
    overrideModificationTime:YES
    debugLogging:NO];

  XCTAssertEqualObjects(command[0], @"-zxpm", @"Flags should include m when overrideMTime is YES");
}

- (void)testCommandToExtractArchive_NoOverrideMTime_WithDebug
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractArchiveAtPath:@"/tmp/archive.tar.gz"
    toPath:@"/tmp/output"
    overrideModificationTime:NO
    debugLogging:YES];

  XCTAssertEqualObjects(command[0], @"-zxpv", @"Flags should include v when debugLogging is YES");
}

- (void)testCommandToExtractArchive_WithOverrideMTime_WithDebug
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractArchiveAtPath:@"/tmp/archive.tar.gz"
    toPath:@"/tmp/output"
    overrideModificationTime:YES
    debugLogging:YES];

  XCTAssertEqualObjects(command[0], @"-zxpmv", @"Flags should include both m and v");
}

- (void)testCommandToExtractArchive_PreservesPathsExactly
{
  NSString *archivePath = @"/Users/test/Downloads/my archive (1).tar.gz";
  NSString *extractPath = @"/Users/test/Documents/output dir";

  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractArchiveAtPath:archivePath
    toPath:extractPath
    overrideModificationTime:NO
    debugLogging:NO];

  XCTAssertEqualObjects(command[2], extractPath, @"Extract path should be preserved exactly");
  XCTAssertEqualObjects(command[4], archivePath, @"Archive path should be preserved exactly");
}

#pragma mark - commandToExtractFromStdIn with GZIP

- (void)testCommandToExtractFromStdIn_GZIPCompression_NoOverrideMTime_NoDebug
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:NO
    compression:FBCompressionFormatGZIP
    debugLogging:NO];

  NSArray<NSString *> *expected = @[@"-zxp", @"-C", @"/tmp/output", @"-f", @"-"];
  XCTAssertEqualObjects(command, expected, @"GZIP extraction should use standard bsdtar flags with stdin");
}

- (void)testCommandToExtractFromStdIn_GZIPCompression_WithOverrideMTime
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:YES
    compression:FBCompressionFormatGZIP
    debugLogging:NO];

  XCTAssertEqualObjects(command[0], @"-zxpm", @"GZIP with overrideMTime should include m flag");
  XCTAssertEqualObjects(command[4], @"-", @"Last element should be stdin marker '-'");
}

#pragma mark - commandToExtractFromStdIn with ZSTD

- (void)testCommandToExtractFromStdIn_ZSTDCompression_NoOverrideMTime
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:NO
    compression:FBCompressionFormatZSTD
    debugLogging:NO];

  NSArray<NSString *> *expected = @[@"--use-compress-program", @"pzstd -d", @"-xp", @"-C", @"/tmp/output", @"-f", @"-"];
  XCTAssertEqualObjects(command, expected, @"ZSTD without overrideMTime should use -xp flags");
}

- (void)testCommandToExtractFromStdIn_ZSTDCompression_WithOverrideMTime
{
  NSArray<NSString *> *command = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:YES
    compression:FBCompressionFormatZSTD
    debugLogging:NO];

  NSArray<NSString *> *expected = @[@"--use-compress-program", @"pzstd -d", @"-xpm", @"-C", @"/tmp/output", @"-f", @"-"];
  XCTAssertEqualObjects(command, expected, @"ZSTD with overrideMTime should use -xpm flags");
}

- (void)testCommandToExtractFromStdIn_ZSTDCompression_IgnoresDebugLogging
{
  // ZSTD path completely replaces the command, so debugLogging flag in flagString is irrelevant
  NSArray<NSString *> *commandNoDebug = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:NO
    compression:FBCompressionFormatZSTD
    debugLogging:NO];

  NSArray<NSString *> *commandWithDebug = [FBArchiveOperations
    commandToExtractFromStdInWithExtractPath:@"/tmp/output"
    overrideModificationTime:NO
    compression:FBCompressionFormatZSTD
    debugLogging:YES];

  // ZSTD path overwrites the entire command, so debug logging doesn't affect the output
  XCTAssertEqualObjects(commandNoDebug, commandWithDebug, @"ZSTD compression should produce the same command regardless of debugLogging");
}

#pragma mark - createGzippedTarForPath with Non-Existent Path

- (void)testCreateGzippedTarForPath_WhenPathDoesNotExist_ReturnsError
{
  NSString *nonExistentPath = @"/tmp/this_path_definitely_does_not_exist_12345";
  FBFuture *future = [FBArchiveOperations createGzippedTarForPath:nonExistentPath logger:_logger];

  NSError *error = nil;
  id result = [future await:&error];
  XCTAssertNil(result, @"Result should be nil for non-existent path");
  XCTAssertNotNil(error, @"Error should be set for non-existent path");
}

- (void)testCreateGzippedTarDataForPath_WhenPathDoesNotExist_ReturnsError
{
  NSString *nonExistentPath = @"/tmp/this_path_definitely_does_not_exist_12345";
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  FBFuture *future = [FBArchiveOperations createGzippedTarDataForPath:nonExistentPath queue:queue logger:_logger];

  NSError *error = nil;
  id result = [future await:&error];
  XCTAssertNil(result, @"Result should be nil for non-existent path");
  XCTAssertNotNil(error, @"Error should be set for non-existent path");
}

- (void)testCreateGzippedTarForPath_WhenPathDoesNotExist_ErrorContainsPath
{
  NSString *nonExistentPath = @"/tmp/nonexistent_path_for_error_check";
  FBFuture *future = [FBArchiveOperations createGzippedTarForPath:nonExistentPath logger:_logger];

  NSError *error = nil;
  [future await:&error];
  XCTAssertNotNil(error, @"Error should be set for non-existent path");
  XCTAssertTrue([error.localizedDescription containsString:nonExistentPath],
    @"Error description should mention the non-existent path, got: %@", error.localizedDescription);
}

#pragma mark - createGzippedTarForPath with Real Paths

- (void)testCreateGzippedTarForPath_WhenPathIsDirectoryWithContent_StartsSubprocess
{
  NSString *filePath = [_tempDirectory stringByAppendingPathComponent:@"testfile.txt"];
  [@"hello" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

  FBFuture *future = [FBArchiveOperations createGzippedTarForPath:_tempDirectory logger:_logger];

  NSError *error = nil;
  FBSubprocess *subprocess = [future await:&error];
  XCTAssertNil(error, @"Starting tar on a valid directory should not produce an error");
  XCTAssertNotNil(subprocess, @"Should return a running subprocess");
  XCTAssertNotNil([subprocess stdOut], @"Subprocess should have an stdout input stream for reading tar data");
}

- (void)testCreateGzippedTarForPath_WhenPathIsFile_StartsSubprocess
{
  NSString *filePath = [_tempDirectory stringByAppendingPathComponent:@"testfile.txt"];
  [@"some content" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

  FBFuture *future = [FBArchiveOperations createGzippedTarForPath:filePath logger:_logger];

  NSError *error = nil;
  FBSubprocess *subprocess = [future await:&error];
  XCTAssertNil(error, @"Starting tar on a valid file should not produce an error");
  XCTAssertNotNil(subprocess, @"Should return a running subprocess");
  XCTAssertNotNil([subprocess stdOut], @"Subprocess should have an stdout input stream for reading tar data");
}

#pragma mark - createGzippedTarDataForPath with Real Paths

- (void)testCreateGzippedTarDataForPath_WhenPathIsDirectory_ProducesData
{
  NSString *filePath = [_tempDirectory stringByAppendingPathComponent:@"data.txt"];
  [@"tar data test" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  FBFuture *future = [FBArchiveOperations createGzippedTarDataForPath:_tempDirectory queue:queue logger:_logger];

  NSError *error = nil;
  NSData *result = [future await:&error];
  XCTAssertNil(error, @"Should not error when tarring a valid directory");
  XCTAssertNotNil(result, @"Should produce tar data");
  XCTAssertGreaterThan(result.length, 0u, @"Tar data should not be empty");
}

- (void)testCreateGzippedTarDataForPath_WhenPathIsFile_ProducesData
{
  NSString *filePath = [_tempDirectory stringByAppendingPathComponent:@"single.txt"];
  [@"file content for tar" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  FBFuture *future = [FBArchiveOperations createGzippedTarDataForPath:filePath queue:queue logger:_logger];

  NSError *error = nil;
  NSData *result = [future await:&error];
  XCTAssertNil(error, @"Should not error when tarring a valid file");
  XCTAssertNotNil(result, @"Should produce tar data for a file");
  XCTAssertGreaterThan(result.length, 0u, @"Tar data for a file should not be empty");
}

- (void)testCreateGzippedTarDataForPath_ProducesValidGzipData
{
  NSString *filePath = [_tempDirectory stringByAppendingPathComponent:@"gzip_check.txt"];
  [@"content to verify gzip format" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  FBFuture *future = [FBArchiveOperations createGzippedTarDataForPath:_tempDirectory queue:queue logger:_logger];

  NSError *error = nil;
  NSData *result = [future await:&error];
  XCTAssertNil(error, @"Should not error when tarring a valid directory");
  XCTAssertNotNil(result, @"Should produce tar data");

  // Verify gzip magic bytes (0x1f, 0x8b) at the start of the data
  XCTAssertGreaterThanOrEqual(result.length, 2u, @"Gzip data should be at least 2 bytes");
  const uint8_t *bytes = (const uint8_t *)result.bytes;
  XCTAssertEqual(bytes[0], 0x1f, @"First byte of gzip data should be 0x1f");
  XCTAssertEqual(bytes[1], 0x8b, @"Second byte of gzip data should be 0x8b");
}

@end
