/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

static int64_t sFileOffset = 0;
static uint64_t sFileMode = 0;
static NSMutableDictionary<NSString *, NSMutableArray<id> *> *sEvents;
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *sVirtualizedFilesAndAttributes;
static NSString *const DirCreateKey = @"dirCreate";
static NSString *const FileCloseKey = @"fileClose";
static NSString *const FileOpenKey = @"fileRefOpen";
static NSString *const RemovePath = @"removePath";
static NSString *const RenamePath = @"renamePath";
static NSString *const FileContentsKey = @"contents";

static void appendPathToEvent(NSString *eventName, const char *path)
{
  NSMutableArray<id> *events = sEvents[eventName];
  [events addObject:[NSString stringWithUTF8String:path]];
}

static void appendPathsToEvent(NSString *eventName, const char *first, const char *second)
{
  NSMutableArray<id> *events = sEvents[eventName];
  [events addObject:@[[NSString stringWithUTF8String:first], [NSString stringWithUTF8String:second]]];
}

static NSArray<NSString *> *contentsOfVirtualizedDirectory(NSString *directory)
{
  NSMutableArray<NSString *> *contents = NSMutableArray.array;
  for (NSString *path in sVirtualizedFilesAndAttributes.allKeys) {
    // Don't add the listed directory to the listing.
    if ([path isEqualToString:directory]) {
      continue;
    }
    NSArray<NSString *> *pathComponents = path.pathComponents;
    // Case for listing of the root, only list paths without nesting.
    BOOL isRootDirectory = directory.length == 0 || [directory isEqualToString:@"/"];
    if (isRootDirectory && pathComponents.count == 1) {
      [contents addObject:path.lastPathComponent];
    }
    // Case for nested directories, just use prefix matching
    if ([path hasPrefix:directory]) {
      [contents addObject:path.lastPathComponent];
    }
  }
  return contents;
}

static char *errorString(int errorCode)
{
  return "some error";
}

static int directoryCreate(AFCConnectionRef connection, const char *dir)
{
  appendPathToEvent(DirCreateKey, dir);
  return 0;
}

static CFDictionaryRef connectionCopyLastErrorInfo(AFCConnectionRef connection)
{
  return (__bridge CFDictionaryRef) @{};
}

static int fileRefOpen(AFCConnectionRef connection, const char *path, FBAFCReadMode mode, CFTypeRef *fileRefOut)
{
  if (sVirtualizedFilesAndAttributes){
    NSString *filePath = [NSString stringWithCString:path encoding:NSASCIIStringEncoding];
    NSString *fileContents = sVirtualizedFilesAndAttributes[filePath][FileContentsKey];
    if (!fileContents) {
      return 1;
    }
  }
  appendPathToEvent(FileOpenKey, path);
  if (fileRefOut) {
    *fileRefOut = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  }
  return 0;
}

static int fileRefSeek(AFCConnectionRef connection, CFTypeRef fileRef, int64_t offset, uint64_t mode)
{
  NSString *filePath = (__bridge NSString *)(fileRef);
  NSString *fileContents = sVirtualizedFilesAndAttributes[filePath][FileContentsKey];
  if (!fileContents) {
    return 1;
  }
  sFileOffset = offset;
  sFileMode = mode;
  return 0;
}

static int fileRefTell(AFCConnectionRef connection, CFTypeRef fileRef, uint64_t *offsetOut)
{
  NSString *filePath = (__bridge NSString *)(fileRef);
  NSString *fileContents = sVirtualizedFilesAndAttributes[filePath][FileContentsKey];
  if (!fileContents) {
    return 1;
  }
  NSData *fileData = [fileContents dataUsingEncoding:NSASCIIStringEncoding];
  if (offsetOut) {
    *offsetOut = fileData.length;
  }
  return 0;
}

static int fileRefRead(AFCConnectionRef connection, CFTypeRef fileRef, void *buffer, uint64_t *lengthOut)
{
  NSString *filePath = (__bridge NSString *)(fileRef);
  NSString *fileContents = sVirtualizedFilesAndAttributes[filePath][FileContentsKey];
  if (!fileContents) {
    return 1;
  }
  NSData *fileData = [fileContents dataUsingEncoding:NSASCIIStringEncoding];
  memcpy(buffer, fileData.bytes, fileData.length);
  return 0;
}

static int fileWrite(AFCConnectionRef connection, CFTypeRef ref, const void *buf, uint64_t length)
{
  return 0;
}

static int fileClose(AFCConnectionRef connection, CFTypeRef ref)
{
  NSString *fileName = (__bridge NSString *)(ref);
  appendPathToEvent(FileCloseKey, fileName.UTF8String);
  CFRelease(ref);
  return 0;
}

static int renamePath(AFCConnectionRef connection, const char *src, const char *dst)
{
  appendPathsToEvent(RenamePath, src, dst);
  return 0;
}

static int removePath(AFCConnectionRef connection, const char *path)
{
  appendPathToEvent(RemovePath, path);
  return 0;
}

static int directoryOpen(AFCConnectionRef connection, const char *path, CFTypeRef *directoryOut)
{
  NSString *pathString = [NSString stringWithCString:path encoding:NSASCIIStringEncoding];
  NSMutableArray<NSString *> *pathsToEnumerate = [contentsOfVirtualizedDirectory(pathString) mutableCopy];
  if (pathsToEnumerate.count == 0) {
    return 1;
  }
  if (directoryOut) {
    *directoryOut = CFBridgingRetain(pathsToEnumerate);
  }
  return 0;
}

static int directoryRead(AFCConnectionRef connection, CFTypeRef dir, char **directoryEntry)
{
  NSMutableArray<NSString *> *pathsToEnumerate = (__bridge NSMutableArray<NSString *> *)(dir);
  if (pathsToEnumerate.count == 0) {
    return 0;
  }
  NSString *next = pathsToEnumerate.firstObject;
  if (directoryEntry) {
    *directoryEntry = (char *) next.UTF8String;
  }
  [pathsToEnumerate removeObjectAtIndex:0];
  return 0;
}

static int directoryClose(AFCConnectionRef connection, CFTypeRef dir)
{
  return 0;
}

static AFCOperationRef operationCreateRemovePathAndContents(CFTypeRef allocator, CFStringRef path, void *unknown_callback_maybe)
{
  NSString *bridged = (__bridge NSString *)(path);
  appendPathToEvent(RemovePath, bridged.UTF8String);
  return CFSTR("empty");
}

static int connectionProcessOperation(AFCConnectionRef connection, CFTypeRef operation)
{
  return 0;
}

static int operationGetResultStatus(CFTypeRef operation)
{
  return 0;
}

static CFTypeRef operationGetResultObject(CFTypeRef operation)
{
  return (__bridge CFTypeRef)(@{});
}

@interface FBAFCConnectionTests : XCTestCase

@property (nonatomic, copy, readonly) NSString *rootHostDirectory;
@property (nonatomic, copy, readonly) NSString *fooHostFilePath;
@property (nonatomic, copy, readonly) NSString *barHostDirectory;
@property (nonatomic, copy, readonly) NSString *bazHostFilePath;

@end

@implementation FBAFCConnectionTests

- (void)setUp
{
  [super setUp];

  sEvents = NSMutableDictionary.dictionary;
  sEvents[DirCreateKey] = NSMutableArray.array;
  sEvents[FileCloseKey] = NSMutableArray.array;
  sEvents[FileOpenKey] = NSMutableArray.array;
  sEvents[RemovePath] = NSMutableArray.array;
  sEvents[RenamePath] = NSMutableArray.array;
  sVirtualizedFilesAndAttributes = nil;

  _rootHostDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_FBAFCConnectionTests", NSUUID.UUID.UUIDString]];
  _fooHostFilePath = [self.rootHostDirectory stringByAppendingPathComponent:@"foo.txt"];
  _barHostDirectory = [self.rootHostDirectory stringByAppendingPathComponent:@"bar"];
  _bazHostFilePath = [self.barHostDirectory stringByAppendingPathComponent:@"baz.empty"];
}

- (void)tearDown
{
  [super tearDown];

  [NSFileManager.defaultManager removeItemAtPath:self.bazHostFilePath error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.barHostDirectory error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.fooHostFilePath error:nil];
  [NSFileManager.defaultManager removeItemAtPath:self.rootHostDirectory error:nil];
}

- (NSDictionary<NSString *, NSArray<id> *> *)events
{
  return [sEvents copy];
}

- (void)addVirtualizedRemoteFiles
{
  sVirtualizedFilesAndAttributes = @{
    @"remote_foo.txt": @{FileContentsKey: @"some foo"},
    @"remote_empty": @{FileContentsKey: @""},
    @"remote_bar": @{@"st_ifmt": @"S_IFDIR"},
    @"remote_bar/some.txt": @{FileContentsKey: @"more nested text"},
    @"remote_bar/other.txt": @{FileContentsKey: @"more other text"},
  };
}

- (AFCConnectionRef)connectionRef
{
  return NULL;
}

static NSString *const FooFileContents = @"FooContents";

- (FBAFCConnection *)setUpConnection
{
  AFCCalls afcCalls = {
    .ConnectionCopyLastErrorInfo = connectionCopyLastErrorInfo,
    .ConnectionProcessOperation = connectionProcessOperation,
    .DirectoryClose = directoryClose,
    .DirectoryCreate = directoryCreate,
    .DirectoryOpen = directoryOpen,
    .DirectoryRead = directoryRead,
    .ErrorString = errorString,
    .FileRefClose = fileClose,
    .FileRefOpen = fileRefOpen,
    .FileRefRead = fileRefRead,
    .FileRefSeek = fileRefSeek,
    .FileRefTell = fileRefTell,
    .FileRefWrite = fileWrite,
    .OperationCreateRemovePathAndContents = operationCreateRemovePathAndContents,
    .OperationGetResultObject = operationGetResultObject,
    .OperationGetResultStatus = operationGetResultStatus,
    .RemovePath = removePath,
    .RenamePath = renamePath,
  };
  // Structure
  // ./foo.txt
  // ./bar
  // ./bar/baz.empty
  NSError *error = nil;
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.rootHostDirectory withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([NSFileManager.defaultManager createDirectoryAtPath:self.barHostDirectory withIntermediateDirectories:YES attributes:nil error:&error]);
  XCTAssertTrue([FooFileContents writeToFile:self.fooHostFilePath atomically:YES encoding:NSASCIIStringEncoding error:&error]);
  XCTAssertTrue([NSData.data writeToFile:self.bazHostFilePath atomically:YES]);

  return [[FBAFCConnection alloc] initWithConnection:self.connectionRef calls:afcCalls logger:nil];
}

- (void)assertExpectedDirectoryCreate:(NSArray<NSString *> *)expectedDirectoryCreate
{
  XCTAssertEqualObjects(expectedDirectoryCreate, self.events[DirCreateKey]);
}

- (void)assertExpectedFiles:(NSArray<NSString *> *)expectedFiles
{
  XCTAssertEqualObjects(expectedFiles, self.events[FileOpenKey]);
  XCTAssertEqualObjects(expectedFiles, self.events[FileCloseKey]);
}

- (void)assertRenameFiles:(NSArray<NSArray<NSString *> *> *)expectedRenameFiles
{
  XCTAssertEqualObjects(expectedRenameFiles, self.events[RenamePath]);
}

- (void)assertRemoveFiles:(NSArray<NSString *> *)expectedRemoveFiles
{
  XCTAssertEqualObjects(expectedRemoveFiles, self.events[RemovePath]);
}

- (void)testRootDirectoryList
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSArray<NSString *> *actual = [connection contentsOfDirectory:@"" error:&error];
  NSArray<NSString *> *expected = @[@"remote_foo.txt", @"remote_empty", @"remote_bar"];
  XCTAssertNil(error);
  XCTAssertEqualObjects(actual, expected);
}

- (void)testNestedDirectoryList
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSArray<NSString *> *actual = [connection contentsOfDirectory:@"remote_bar" error:&error];
  NSArray<NSString *> *expected = @[@"some.txt", @"other.txt"];
  XCTAssertNil(error);
  XCTAssertEqualObjects(actual, expected);
}

- (void)testMissingDirectoryFail
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSArray<NSString *> *actual = [connection contentsOfDirectory:@"aaaaaa" error:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(actual);
}

- (void)testReadsFile
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSData *expected = [@"some foo" dataUsingEncoding:NSASCIIStringEncoding];
  NSData *actual = [connection contentsOfPath:@"remote_foo.txt" error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(expected, actual);
}

- (void)testFailsToReadDirectory
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSData *actual = [connection contentsOfPath:@"remote_bar" error:&error];
  XCTAssertNil(actual);
  XCTAssertNotNil(error);
}

- (void)testFailsToReadMissingFile
{
  FBAFCConnection *connection = [self setUpConnection];
  [self addVirtualizedRemoteFiles];
  NSError *error = nil;
  NSData *actual = [connection contentsOfPath:@"nope" error:&error];
  XCTAssertNil(actual);
  XCTAssertNotNil(error);
}

- (void)testCopySingleFileToRoot
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection copyFromHost:self.fooHostFilePath toContainerPath:@"" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertExpectedDirectoryCreate:@[]];
  [self assertExpectedFiles:@[
    @"foo.txt",
  ]];
}

- (void)testCopyFileToContainerPath
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection copyFromHost:self.fooHostFilePath toContainerPath:@"bing" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertExpectedDirectoryCreate:@[]];
  [self assertExpectedFiles:@[
    @"bing/foo.txt",
  ]];
}

- (void)testCopyItemsFromHostDirectory
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection copyFromHost:self.rootHostDirectory toContainerPath:@"" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertExpectedDirectoryCreate:@[
    self.rootHostDirectory.lastPathComponent,
    [self.rootHostDirectory.lastPathComponent stringByAppendingPathComponent:@"bar"],
  ]];
  [self assertExpectedFiles:@[
    [self.rootHostDirectory.lastPathComponent stringByAppendingPathComponent:@"foo.txt"],
    [self.rootHostDirectory.lastPathComponent stringByAppendingPathComponent:@"bar/baz.empty"],
  ]];
}

- (void)testCreateDirectoryAtRoot
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection createDirectory:@"bing" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertExpectedDirectoryCreate:@[@"bing"]];
}

- (void)testCreateDirectoryInsideDirectory
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection createDirectory:@"bar/bing" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertExpectedDirectoryCreate:@[@"bar/bing"]];
}

- (void)testRenamePath
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection renamePath:@"foo.txt" destination:@"bar.txt" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertRenameFiles:@[@[@"foo.txt", @"bar.txt"]]];
}

- (void)testRemovePath
{
  FBAFCConnection *connection = [self setUpConnection];
  NSError *error = nil;
  BOOL success = [connection removePath:@"foo.txt" recursively:YES error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertRemoveFiles:@[@"foo.txt"]];
}

@end
