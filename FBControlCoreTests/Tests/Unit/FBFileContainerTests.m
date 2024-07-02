/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"

@interface FBFileContainerTests : XCTestCase

@property (nonatomic, copy, readonly) NSString *basePathTestBasePath;
@property (nonatomic, copy, readonly) NSString *basePathPulledFileTestBasePath;
@property (nonatomic, copy, readonly) NSString *basePathPulledDirectoryTestBasePath;
@property (nonatomic, copy, readonly) NSString *basePathTestPathMappingFoo;
@property (nonatomic, copy, readonly) NSString *basePathTestPathMappingBar;
@property (nonatomic, copy, readonly) NSString *basePathPulledFileTestPathMapping;
@property (nonatomic, copy, readonly) NSString *basePathPulledDirectoryTestPathMapping;
@property (nonatomic, copy, readonly) NSString *basePathPulledMappedDirectoryTestPathMapping;
@end

@implementation FBFileContainerTests

- (void)setUp
{
  [super setUp];

  _basePathTestBasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testBasePath", NSUUID.UUID.UUIDString]];
  _basePathPulledFileTestBasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testBasePath_pulled_file", NSUUID.UUID.UUIDString]];
  _basePathPulledDirectoryTestBasePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testBasePath_pulled_directory", NSUUID.UUID.UUIDString]];
  _basePathTestPathMappingFoo =[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testPathMapping_foo", NSUUID.UUID.UUIDString]];
  _basePathTestPathMappingBar = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testPathMapping_bar", NSUUID.UUID.UUIDString]];
  _basePathPulledFileTestPathMapping = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testPathMapping_pulled_file", NSUUID.UUID.UUIDString]];;
  _basePathPulledDirectoryTestPathMapping = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testPathMapping_pulled_directory", NSUUID.UUID.UUIDString]];
  _basePathPulledMappedDirectoryTestPathMapping = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBSimulatorFileCommandsTests_testPathMapping_pulled_mapped_directory", NSUUID.UUID.UUIDString]];
}

- (void)tearDown
{
  [super tearDown];

  [NSFileManager.defaultManager removeItemAtPath:self.basePathTestBasePath error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathPulledFileTestBasePath error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathPulledDirectoryTestBasePath error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathTestPathMappingFoo error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathTestPathMappingBar error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathPulledFileTestPathMapping error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathPulledDirectoryTestPathMapping error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.basePathPulledMappedDirectoryTestPathMapping error:nil];
}

- (NSString *)basePath
{
  return self.basePathTestBasePath;
}

- (NSString *)fileInBasePath
{
  return [self.basePath stringByAppendingPathComponent:@"file.txt"];
}

- (NSString *)directoryInBasePath
{
  return [self.basePath stringByAppendingPathComponent:@"dir"];
}

- (NSString *)fileInDirectoryInBasePath
{
  return [self.directoryInBasePath stringByAppendingPathComponent:@"some.txt"];
}

static NSString *const FileInBasePathText = @"Some Text";
static NSString *const FileInDirectoryInBasePathText = @"Other Text";

- (id<FBFileContainer>)setUpBasePathContainer
{
  NSError *error = nil;
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.directoryInBasePath withIntermediateDirectories:YES attributes:nil error:&error]);

  XCTAssertTrue([FileInBasePathText writeToFile:self.fileInBasePath atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  XCTAssertTrue([FileInDirectoryInBasePathText writeToFile:self.fileInDirectoryInBasePath atomically:YES encoding:NSUTF8StringEncoding error:&error]);

  return [FBFileContainer fileContainerForBasePath:self.basePath];
}

- (NSString *)fooPath
{
  return self.basePathTestPathMappingFoo;
}

- (NSString *)fileInFoo
{
  return [self.fooPath stringByAppendingPathComponent:@"file.txt"];
}

- (NSString *)barPath
{
  return self.basePathTestPathMappingBar;
}

- (NSString *)directoryInBar
{
  return [self.barPath stringByAppendingPathComponent:@"dir"];
}

- (NSString *)fileInDirectoryInBar
{
  return [self.directoryInBar stringByAppendingPathComponent:@"in_dir.txt"];
}

NSString *FileInFooText = @"Some Text";
NSString *FileInDirectoryInBarText = @"Other Text";

- (id<FBFileContainer>)setUpMappedPathContainer
{
  NSError *error = nil;
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.fooPath withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.barPath withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.directoryInBar withIntermediateDirectories:YES attributes:nil error:&error]);

  XCTAssertTrue([FileInFooText writeToFile:self.fileInFoo atomically:YES encoding:NSUTF8StringEncoding error:&error]);
  XCTAssertTrue([FileInDirectoryInBarText writeToFile:self.fileInDirectoryInBar atomically:YES encoding:NSUTF8StringEncoding error:&error]);

  NSDictionary<NSString *, NSString *> *pathMapping = @{@"foo": self.fooPath, @"bar": self.barPath};
  return [FBFileContainer fileContainerForPathMapping:pathMapping];
}

- (void)testBasePathDirectoryListingAtRoot
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"file.txt", @"dir"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"."] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testBasePathDirectoryListingAtSubdirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  // Listing a dir that doesn't exist fails.
  XCTAssertNil([[container contentsOfDirectory:@"no_dir"] await:nil]);
}

- (void)testBasePathPullFile
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSString *pulledFileDirectory = self.basePathPulledFileTestBasePath;
  NSString *pulledFile = [[container copyFromContainer:@"file.txt" toHost:pulledFileDirectory] await:&error];
  pulledFile = [pulledFile stringByAppendingPathComponent:@"file.txt"];
  XCTAssertNil(error);
  XCTAssertNotNil(pulledFile);
  NSString *actualContent = [NSString stringWithContentsOfFile:pulledFile encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(actualContent);
  NSString *expectedContent = FileInBasePathText;
  XCTAssertEqualObjects(actualContent, expectedContent);
}

- (void)testBasePathPullFileFromDirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSString *pulledFileDirectory = self.basePathPulledFileTestBasePath;
  NSString *pulledFile = [[container copyFromContainer:@"dir/some.txt" toHost:pulledFileDirectory] await:&error];
  pulledFile = [pulledFile stringByAppendingPathComponent:@"some.txt"];
  NSString *actualContent = [NSString stringWithContentsOfFile:pulledFile encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(actualContent);
  NSString *expectedContent = FileInDirectoryInBasePathText;
  XCTAssertEqualObjects(actualContent, expectedContent);
}

- (void)testBasePathPullEntireDirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSString *pulledDirectoryDirectory = self.basePathPulledDirectoryTestBasePath;
  NSString *pulledDirectory = [[container copyFromContainer:@"dir" toHost:pulledDirectoryDirectory] await:&error];
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt"]];
  NSArray<NSString *> *actualFiles = [NSFileManager.defaultManager contentsOfDirectoryAtPath:pulledDirectory error:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testBasePathCreateDirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error =nil;
  XCTAssertNotNil([[container createDirectory:@"other"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"file.txt", @"dir", @"other"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"."] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertNotNil([[container createDirectory:@"other/nested/here"] await:&error]);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"nested"]];
  actualFiles = [[container contentsOfDirectory:@"other"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"here"]];
  actualFiles = [[container contentsOfDirectory:@"other/nested"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
}

- (void)testBasePathPushFile
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSString *pushedFile = FBControlCoreFixtures.photo0Path;
  XCTAssertNotNil([[container copyFromHost:pushedFile toContainer:@"dir"] await:&error]);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt", @"photo0.png"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testBasePathPushDirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  NSString *pushedDirectory = FBControlCoreFixtures.photo0Path.stringByDeletingLastPathComponent;
  XCTAssertNotNil([[container copyFromHost:pushedDirectory toContainer:@"dir"] await:&error]);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt", @"Resources"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  expectedFiles = [NSSet setWithArray:@[
    @"xctest",
    @"app_custom_set.crash",
    @"tree.json",
    @"app_default_set.crash",
    @"assetsd_custom_set.crash",
    @"xctest-concated-json-crash.ips",
    @"agent_custom_set.crash",
    @"photo0.png",
    @"simulator_system.log",
  ]];
  actualFiles = [[container contentsOfDirectory:@"dir/Resources"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testBasePathMoveFile
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container moveFrom:@"file.txt" to:@"dir/file.txt"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt", @"file.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testBasePathMoveDirectory
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container moveFrom:@"dir" to:@"moved_dir"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"some.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"moved_dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  XCTAssertNil([[container contentsOfDirectory:@"dir"] await:nil]);
  // Then back again.
  XCTAssertNotNil([[container moveFrom:@"moved_dir" to:@"dir"] await:&error]);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"some.txt"]];
  actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  XCTAssertNil([[container contentsOfDirectory:@"moved_dir"] await:nil]);
}

- (void)testBasePathDeleteFile
{
  id<FBFileContainer> container = [self setUpBasePathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container remove:@"dir/some.txt"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  XCTAssertNotNil([[container remove:@"dir"] await:&error]);
  XCTAssertNil(error);
  actualFiles = [[container contentsOfDirectory:@"dir"] await:nil];
  XCTAssertNil(actualFiles);
}

- (void)testMappedPathDirectoryListingAtRoot
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"foo", @"bar"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"."] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathDirectoryListingInsideMapping
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"file.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"foo"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  expectedFiles = [NSSet setWithArray:@[@"dir"]];
  actualFiles = [[container contentsOfDirectory:@"bar"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  expectedFiles = [NSSet setWithArray:@[@"in_dir.txt"]];
  actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathDirectoryListingOfNonExistentDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  XCTAssertNil([[container contentsOfDirectory:@"no_dir"] await:nil]);
}

- (void)testMappedPathPullFile
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pulledFileDirectory = self.basePathPulledFileTestPathMapping;
  NSString *pulledFile = [[container copyFromContainer:@"foo/file.txt" toHost:pulledFileDirectory] await:&error];
  pulledFile = [pulledFile stringByAppendingPathComponent:@"file.txt"];
  NSString *actualContent = [NSString stringWithContentsOfFile:pulledFile encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(actualContent);
  NSString *expectedContent = FileInFooText;
  XCTAssertEqualObjects(actualContent, expectedContent);
}

- (void)testMappedPathPullFileInMappedDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pulledFileDirectory = self.basePathPulledFileTestPathMapping;
  NSString *pulledFile = [[container copyFromContainer:@"bar/dir/in_dir.txt" toHost:pulledFileDirectory] await:&error];
  pulledFile = [pulledFile stringByAppendingPathComponent:@"in_dir.txt"];
  NSString *actualContent = [NSString stringWithContentsOfFile:pulledFile encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(actualContent);
  NSString *expectedContent = FileInDirectoryInBarText;
  XCTAssertEqualObjects(actualContent, expectedContent);
}

- (void)testMappedPathPullDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pulledDirectoryDirectory = self.basePathPulledDirectoryTestPathMapping;
  NSString *pulledDirectory = [[container copyFromContainer:@"bar/dir" toHost:pulledDirectoryDirectory] await:&error];
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"in_dir.txt"]];
  NSArray<NSString *> *actualFiles = [NSFileManager.defaultManager contentsOfDirectoryAtPath:pulledDirectory error:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathPullRootPath
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pulledDirectoryDirectory = self.basePathPulledMappedDirectoryTestPathMapping;
  NSString *pulledDirectory = [[container copyFromContainer:@"bar" toHost:pulledDirectoryDirectory] await:&error];
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"dir"]];
  NSArray<NSString *> *actualFiles = [NSFileManager.defaultManager contentsOfDirectoryAtPath:pulledDirectory error:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathCreateDirectoryInContainer
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container createDirectory:@"foo/other"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"file.txt", @"dir", @"other"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"foo"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertNotNil([[container createDirectory:@"foo/other/nested/here"] await:&error]);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"nested"]];
  actualFiles = [[container contentsOfDirectory:@"foo/other"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"here"]];
  actualFiles = [[container contentsOfDirectory:@"foo/other/nested"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
}

- (void)testMappedPathCreateDirectoryAtRootFails
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  XCTAssertNil([[container createDirectory:@"no_create"] await:nil]);
}

- (void)testMappedPathPushFile
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pushedFile = FBControlCoreFixtures.photo0Path;
  XCTAssertNotNil([[container copyFromHost:pushedFile toContainer:@"bar/dir"] await:&error]);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"in_dir.txt", @"photo0.png"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathPushDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  NSString *pushedDirectory = FBControlCoreFixtures.photo0Path.stringByDeletingLastPathComponent;
  XCTAssertNotNil([[container copyFromHost:pushedDirectory toContainer:@"bar/dir"] await:&error]);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"in_dir.txt", @"Resources"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  expectedFiles = [NSSet setWithArray:@[
    @"xctest",
    @"app_custom_set.crash",
    @"tree.json",
    @"app_default_set.crash",
    @"assetsd_custom_set.crash",
    @"xctest-concated-json-crash.ips",
    @"agent_custom_set.crash",
    @"photo0.png",
    @"simulator_system.log",
  ]];
  actualFiles = [[container contentsOfDirectory:@"bar/dir/Resources"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathPushToRootFails
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSString *pushedFile = FBControlCoreFixtures.photo0Path;
  XCTAssertNil([[container copyFromHost:pushedFile toContainer:@"."] await:nil]);
}

- (void)testMappedPathMoveFile
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container moveFrom:@"foo/file.txt" to:@"bar/dir/file.txt"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"in_dir.txt", @"file.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathMoveDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container moveFrom:@"bar/dir" to:@"bar/moved_dir"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[@"in_dir.txt"]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/moved_dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  XCTAssertNil([[container contentsOfDirectory:@"bar/dir"] await:nil]);
  // Then back again.
  XCTAssertNotNil([[container moveFrom:@"bar/moved_dir" to:@"bar/dir"] await:&error]);
  XCTAssertNil(error);
  expectedFiles = [NSSet setWithArray:@[@"in_dir.txt",]];
  actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
  XCTAssertNil([[container contentsOfDirectory:@"bar/moved_dir"] await:nil]);
}

- (void)testMappedPathDeleteFile
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container remove:@"bar/dir/in_dir.txt"] await:&error]);
  XCTAssertNil(error);
  NSSet<NSString *> *expectedFiles = [NSSet setWithArray:@[]];
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:&error];
  XCTAssertNotNil(actualFiles);
  XCTAssertNil(error);
  XCTAssertEqualObjects(expectedFiles, [NSSet setWithArray:actualFiles]);
}

- (void)testMappedPathDeleteDirectory
{
  id<FBFileContainer> container = [self setUpMappedPathContainer];
  NSError *error = nil;
  XCTAssertNotNil([[container remove:@"bar/dir"] await:&error]);
  XCTAssertNil(error);
  NSArray<NSString *> *actualFiles = [[container contentsOfDirectory:@"bar/dir"] await:nil];
  XCTAssertNil(actualFiles);
  // Deleting a root fails
  XCTAssertNil([[container remove:@"."] await:nil]);
}

@end
