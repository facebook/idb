/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBAFCConnectionTests : XCTestCase

@property (nonatomic, strong, readwrite, class) NSMutableDictionary<NSString *, id> *events;

@end

static void appendToEvent(NSString *eventName, const char *text) {
  NSMutableArray<NSString *> *dirs = FBAFCConnectionTests.events[eventName];
  if (!dirs) {
    dirs = [NSMutableArray new];
    FBAFCConnectionTests.events[eventName] = dirs;
  }
  [dirs addObject:[NSString stringWithUTF8String:text]];
}

static int dirCreateSuccess(AFCConnectionRef connection, const char *dir) {
  appendToEvent(@"dirCreate", dir);
  return 0;
}

static int fileOpen(AFCConnectionRef connection, const char *_Nonnull path, FBAFCReadMode mode, CFTypeRef *_Nonnull ref) {
  appendToEvent(@"fileOpen", path);
  *ref = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
  return 0;
}

static int fileWrite(AFCConnectionRef connection, CFTypeRef ref, const void *buf, uint64_t len) {
  return 0;
}

static int fileClose(AFCConnectionRef connection, CFTypeRef ref) {
  NSString *fileName = (__bridge NSString *)(ref);
  appendToEvent(@"fileClose", fileName.UTF8String);
  CFRelease(ref);
  return 0;
}

@implementation FBAFCConnectionTests

static NSMutableDictionary *sEvents;

+ (NSMutableDictionary *)events
{
  if (!sEvents){
    sEvents = [NSMutableDictionary dictionary];
  }
  return sEvents;
}

+ (void)setEvents:(NSMutableDictionary *)events
{
  sEvents = events;
}

- (AFCConnectionRef)connectionRef
{
  return NULL;
}

- (void)testCopyItemsAtPath
{
  AFCCalls afcCalls = {
    .DirectoryCreate = dirCreateSuccess,
    .FileRefOpen = fileOpen,
    .FileRefWrite = fileWrite,
    .FileRefClose = fileClose,
  };

  FBAFCConnection *connection = [[FBAFCConnection alloc] initWithConnection:self.connectionRef calls:afcCalls logger:nil];

  /** Structure
    ./{UUID}
    ./{UUID}/file.empty
    ./{UUID}/{UUID2}/file2.txt
  */
  NSString *dir = [[NSUUID UUID] UUIDString];
  NSString *dir2 = [[NSUUID UUID] UUIDString];
  NSString *pathStr = [NSTemporaryDirectory() stringByAppendingPathComponent:dir];
  NSURL *path = [NSURL fileURLWithPath:pathStr];
  NSArray<NSString *> *expectedDirs = @[dir, [@[dir, dir2] componentsJoinedByString:@"/"]];

  [[NSFileManager defaultManager] createDirectoryAtURL:[path URLByAppendingPathComponent:dir2 isDirectory:YES] withIntermediateDirectories:YES attributes:nil error:NULL];
  [[NSData data] writeToURL:[path URLByAppendingPathComponent:@"file.empty"] atomically:YES];
  [[NSData data] writeToURL:[path URLByAppendingPathComponent:[NSString pathWithComponents:@[dir2, @"file2.txt"]]] atomically:YES];

  NSSet<NSString *> *files = [NSSet setWithArray:@[
    [dir stringByAppendingFormat:@"/%@", @"file.empty"],
    [@[dir, dir2, @"file2.txt"] componentsJoinedByString:@"/"]
  ]];

  NSError *error = nil;
  BOOL success = [connection copyFromHost:path toContainerPath:@"" error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  XCTAssertEqualObjects(expectedDirs, self.class.events[@"dirCreate"]);
  XCTAssertEqualObjects(files, [NSSet setWithArray:self.class.events[@"fileClose"]]);
  XCTAssertEqualObjects(self.class.events[@"fileOpen"], self.class.events[@"fileClose"]);
}

@end
