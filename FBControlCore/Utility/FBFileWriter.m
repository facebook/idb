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

@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;
@property (nonatomic, strong, readwrite) FBMutableFuture<NSNull *> *eofHasBeenReceivedMutable;

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle;

@end

@interface FBFileWriter_Null : FBFileWriter <FBDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Sync : FBFileWriter <FBDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Async : FBFileWriter <FBDataConsumer, FBDataConsumerLifecycle>

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readwrite) dispatch_io_t io;

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

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)nullWriter
{
  return [[FBFileWriter_Null alloc] init];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterWithFileHandle:(NSFileHandle *)fileHandle
{
  return [[FBFileWriter_Sync alloc] initWithFileHandle:fileHandle];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle queue:(dispatch_queue_t)queue error:(NSError **)error
{
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:queue];
  if (![writer startReadingWithError:error]) {
    return nil;
  }
  return writer;
}

+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncDispatchDataWriterWithFileHandle:(NSFileHandle *)fileHandle
{
  NSError *error = nil;
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:self.createWorkQueue];
  if (![writer startReadingWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:writer];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle error:(NSError **)error
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [self asyncWriterWithFileHandle:fileHandle queue:queue error:error];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error
{
  NSFileHandle *fileHandle = [self fileHandleForPath:filePath error:error];
  if (!fileHandle) {
    return nil;
  }
  return [FBFileWriter syncWriterWithFileHandle:fileHandle];
}

+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncWriterForFilePath:(NSString *)filePath
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
  _eofHasBeenReceivedMutable = [FBMutableFuture futureWithName:@"EOF Recieved"];

  return self;
}

@end

@implementation FBFileWriter_Null

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  // do nothing
}

- (void)consumeEndOfFile
{
  [self.eofHasBeenReceivedMutable resolveWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedMutable;
}

@end

@implementation FBFileWriter_Sync

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [self.fileHandle writeData:data];
}

- (void)consumeEndOfFile
{
  [self.eofHasBeenReceivedMutable resolveWithResult:NSNull.null];
  [self.fileHandle closeFile];
  self.fileHandle = nil;
}

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedMutable;
}

@end

@implementation FBFileWriter_Async

#pragma mark Initializers

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super initWithFileHandle:fileHandle];
  if (!self) {
    return nil;
  }

  _writeQueue = writeQueue;

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  NSParameterAssert(self.io);

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

- (void)consumeEndOfFile
{
  NSParameterAssert(self.io);
  [self.eofHasBeenReceivedMutable resolveWithResult:NSNull.null];

  // We can't close the file handle right now since there may still be pending IO operations on the channel.
  // The safe place to do this is within the dispatch_io_create cleanup_handler callback.
  // Until the cleanup_handler is called, libdispatch takes over control of the file descriptor.
  // We also want to ensure that there are no pending write operations on the channel, otherwise it's easy to miss data.
  // The barrier ensures that there are no pending writes before we attempt to interrupt the channel.
  dispatch_io_barrier(self.io, ^{
    dispatch_io_close(self.io, DISPATCH_IO_STOP);
  });
}

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedMutable;
}

#pragma mark Private

- (BOOL)startReadingWithError:(NSError **)error
{
  NSParameterAssert(!self.io);

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  NSFileHandle *fileHandle = self.fileHandle;
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.writeQueue, ^(int errorCode) {
    [self ioChannelDidCloseWithError:errorCode];
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

- (void)ioChannelDidCloseWithError:(int)errorCode
{
  [self.fileHandle closeFile];
  self.fileHandle = nil;
  self.io = nil;
}

@end
