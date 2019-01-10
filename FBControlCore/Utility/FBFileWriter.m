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

@interface FBFileWriter () <FBDataConsumer>

@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle;

@end

@interface FBFileWriter_Null : FBFileWriter

@end

@interface FBFileWriter_Sync : FBFileWriter

@end

@interface FBFileWriter_Async : FBFileWriter

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;

@property (nonatomic, strong, readwrite) dispatch_io_t io;
@property (nonatomic, assign, readwrite) int errorCode;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle writeQueue:(dispatch_queue_t)writeQueue;

- (BOOL)startReadingWithError:(NSError **)error;

@end

@implementation FBFileWriter

#pragma mark Initializers

+ (dispatch_queue_t)createWorkQueue
{
  return dispatch_queue_create("com.facebook.fbcontrolcore.fbfilewriter", DISPATCH_QUEUE_SERIAL);;
}

+ (nullable NSFileHandle *)fileHandleForPath:(NSString *)filePath error:(NSError **)error
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
  return fileHandle;
}

+ (id<FBDataConsumer>)nullWriter
{
  return [[FBFileWriter_Null alloc] init];
}

+ (id<FBDataConsumer>)syncWriterWithFileHandle:(NSFileHandle *)fileHandle
{
  return [[FBFileWriter_Sync alloc] initWithFileHandle:fileHandle];
}

+ (id<FBDataConsumer>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle queue:(dispatch_queue_t)queue error:(NSError **)error
{
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:queue];
  if (![writer startReadingWithError:error]) {
    return nil;
  }
  return writer;
}

+ (id<FBDataConsumer>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle error:(NSError **)error
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [self asyncWriterWithFileHandle:fileHandle queue:queue error:error];
}

+ (id<FBDataConsumer>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error
{
  NSFileHandle *fileHandle = [self fileHandleForPath:filePath error:error];
  if (!fileHandle) {
    return nil;
  }
  return [FBFileWriter syncWriterWithFileHandle:fileHandle];
}

+ (FBFuture<id<FBDataConsumer>> *)asyncWriterForFilePath:(NSString *)filePath
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [[FBFuture
    onQueue:queue resolveValue:^(NSError **error) {
      return [FBFileWriter fileHandleForPath:filePath error:error];
    }]
    onQueue:queue fmap:^(NSFileHandle *fileHandle) {
      FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:queue];
      NSError *error = nil;
      if (![writer startReadingWithError:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:writer];
    }];
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

#pragma mark Public Methods

- (void)consumeData:(NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)consumeEndOfFile
{
  [self consumeEndOfFileClosingFileHandle:YES];
}

#pragma mark Private

- (void)consumeEndOfFileClosingFileHandle:(BOOL)close
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

#pragma mark NSObject

- (void)dealloc
{
  // Cleans up resources, but don't force-close the file handle.
  [self consumeEndOfFileClosingFileHandle:NO];
}

@end

@implementation FBFileWriter_Null

- (void)consumeData:(NSData *)data
{
  // do nothing
}

- (void)consumeEndOfFileClosingFileHandle:(BOOL)close
{
  // do nothing
}

@end

@implementation FBFileWriter_Sync

- (void)consumeData:(NSData *)data
{
  [self.fileHandle writeData:data];
}

- (void)consumeEndOfFileClosingFileHandle:(BOOL)close
{
  if (close) {
    [self.fileHandle closeFile];
  }
  self.fileHandle = nil;
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

#pragma mark Lifecycle

- (BOOL)startReadingWithError:(NSError **)error
{
  NSParameterAssert(self.io == NULL);
  NSFileHandle *fileHandle = self.fileHandle;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.writeQueue, ^(int errorCode) {
    self.errorCode = errorCode;
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", fileHandle.fileDescriptor]
      failBool:error];
  }

  // Report partial results with as little as 1 byte read.
  dispatch_io_set_low_water(self.io, 1);
  return YES;
}

- (void)consumeData:(NSData *)data
{
  if (!self.io) {
    return;
  }

  // The safest possible way of adapting the NSData to dispatch_data_t is to ensure that buffer backing the dispatch_data_t data is:
  // 1) Immutable
  // 2) Is not freed until the dispatch_data_t is destroyed.
  // There are two ways of doing this:
  // 1) Copy the NSData, and retain it for the lifecycle of the dispatch_data_t.
  // 2) Use DISPATCH_DATA_DESTRUCTOR_DEFAULT which will copy the underlying buffer.
  // This uses #2 as it's preferable to let libdispatch do the management itself and avoids an object copy (NSData) as well as a potential buffer copy in `-[NSData copy]`.
  // It can be quite surprising how many methods result in the creation of NSMutableData, for example `-[NSString dataUsingEncoding:]` can result in NSConcreteMutableData.
  // By copying the buffer we are sure that the data in the dispatch wrapper is completely immutable.
  dispatch_data_t dispatchData = dispatch_data_create(
    data.bytes,
    data.length,
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    DISPATCH_DATA_DESTRUCTOR_DEFAULT
  );
  dispatch_io_write(self.io, 0, dispatchData, self.writeQueue, ^(bool done, dispatch_data_t remainder, int error) {});
}

- (void)consumeEndOfFileClosingFileHandle:(BOOL)close
{
  if (!self.io) {
    return;
  }

  // Remove resources form self to be closed in the io barrier.
  NSFileHandle *fileHandle = self.fileHandle;
  self.fileHandle = nil;
  dispatch_io_t io = self.io;
  self.io = nil;

  // Wait for all io operations to stop with a barrier, then close the io channel
  dispatch_io_barrier(io, ^{
    dispatch_io_close(io, DISPATCH_IO_STOP);
    if (close) {
      [fileHandle closeFile];
    }
  });
}

@end
