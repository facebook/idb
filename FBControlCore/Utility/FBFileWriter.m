/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFileWriter.h"

#import "FBControlCoreError.h"

@interface FBFileWriter ()

@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle;

@end

@interface FBFileWriter_Sync : FBFileWriter

@end

@interface FBFileWriter_Async : FBFileWriter

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle writeQueue:(dispatch_queue_t)writeQueue;

@end

@implementation FBFileWriter

+ (instancetype)writerWithFileHandle:(NSFileHandle *)fileHandle blocking:(BOOL)blocking
{
  if (blocking) {
    return [[FBFileWriter_Sync alloc] initWithFileHandle:fileHandle];
  }
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.fbfilewriter", DISPATCH_QUEUE_SERIAL);
  return [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:queue];
}

+ (nullable instancetype)writerForFilePath:(NSString *)filePath blocking:(BOOL)blocking error:(NSError **)error
{
  if (![NSFileManager.defaultManager fileExistsAtPath:filePath]) {
    [[NSData data] writeToFile:filePath atomically:YES];
  }
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
  if (!fileHandle) {
    return [[FBControlCoreError
      describeFormat:@"A file handle for path %@ could not be opened", filePath]
      fail:error];
  }
  return [FBFileWriter writerWithFileHandle:fileHandle blocking:blocking];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;

  return self;
}

- (void)consumeData:(NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)consumeEndOfFile
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

@end

@implementation FBFileWriter_Sync

- (void)consumeData:(NSData *)data
{
  NSFileHandle *fileHandle = self.fileHandle;
  [fileHandle writeData:data];
}

- (void)consumeEndOfFile
{
  NSFileHandle *fileHandle = self.fileHandle;
  [fileHandle closeFile];
}

@end

@implementation FBFileWriter_Async

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super initWithFileHandle:fileHandle];
  if (!self) {
    return nil;
  }

  _writeQueue = writeQueue;

  return self;
}

#pragma mark FBFileConsumer Implementation

- (void)consumeData:(NSData *)data
{
  NSFileHandle *fileHandle = self.fileHandle;
  dispatch_async(self.writeQueue, ^{
    [fileHandle writeData:data];
  });
}

- (void)consumeEndOfFile
{
  NSFileHandle *fileHandle = self.fileHandle;
  dispatch_async(self.writeQueue, ^{
    [fileHandle closeFile];
  });
}

@end
