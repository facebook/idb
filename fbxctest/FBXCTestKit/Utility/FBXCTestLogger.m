/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestLogger.h"

static NSString *const OutputLogDirectoryEnv = @"FBXCTEST_LOG_DIRECTORY";

@interface FBXCTestLogger ()

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> baseLogger;

@end

@implementation FBXCTestLogger

+ (NSString *)logDirectory
{
  NSString *directory = NSProcessInfo.processInfo.environment[OutputLogDirectoryEnv];
  if (directory) {
    return directory;
  }
  directory = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:@"tmp"];
  if ([NSFileManager.defaultManager fileExistsAtPath:directory]) {
    return directory;
  }
  return NSTemporaryDirectory();
}

+ (instancetype)defaultLoggerInDefaultDirectory
{
  NSString *name = [NSString stringWithFormat:@"%@_test.log", NSProcessInfo.processInfo.globallyUniqueString];
  return [self loggerInDefaultDirectory:name];
}

+ (instancetype)loggerInDefaultDirectory:(NSString *)name
{
  NSString *path = [self.logDirectory stringByAppendingPathComponent:name];

  BOOL success = [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
  NSAssert(success, @"Expected to create file at path %@, but could not", path);
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
  NSAssert(fileHandle, @"Could not create a writable file handle for file at path %@", fileHandle);

  id<FBControlCoreLogger> baseLogger = [FBControlCoreLogger aslLoggerWritingToFileDescriptor:fileHandle.fileDescriptor withDebugLogging:YES];

  return [[self alloc] initWithBaseLogger:baseLogger filePath:path fileHandle:fileHandle];
}

- (instancetype)initWithBaseLogger:(id<FBControlCoreLogger>)baseLogger filePath:(NSString *)filePath fileHandle:(NSFileHandle *)fileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _fileHandle = fileHandle;
  _baseLogger = baseLogger;

  return self;
}

- (nullable NSString *)lastLinesOfOutput:(NSUInteger)lineCount
{
  NSString *output = [self allLinesOfOutput];
  if (!output) {
    return nil;
  }
  NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  NSUInteger startPosition = lines.count < lineCount ? 0 : lines.count - lineCount;
  NSRange requestedRange = NSMakeRange(startPosition, lineCount);
  NSRange entireRange = NSMakeRange(0, lines.count);
  NSRange availableRange = NSIntersectionRange(requestedRange, entireRange);
  return [[lines
    subarrayWithRange:availableRange]
    componentsJoinedByString:@"\n"];
}

- (nullable NSString *)allLinesOfOutput
{
  return [NSString stringWithContentsOfFile:self.filePath encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark Protocol Implementation

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  [self.baseLogger log:string];
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2)
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [[self.class alloc]
    initWithBaseLogger:[self.baseLogger info]
    filePath:self.filePath
    fileHandle:self.fileHandle];
}

- (id<FBControlCoreLogger>)debug
{
  return [[self.class alloc]
    initWithBaseLogger:[self.baseLogger debug]
    filePath:self.filePath
    fileHandle:self.fileHandle];
}

- (id<FBControlCoreLogger>)error
{
  return [[self.class alloc]
  initWithBaseLogger:[self.baseLogger error]
  filePath:self.filePath
  fileHandle:self.fileHandle];
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  return [[self.class alloc]
    initWithBaseLogger:[self.baseLogger onQueue:queue]
    filePath:self.filePath
    fileHandle:self.fileHandle];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return [[self.class alloc]
    initWithBaseLogger:[self.baseLogger withPrefix:prefix]
    filePath:self.filePath
    fileHandle:self.fileHandle];
}

@end
