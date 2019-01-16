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

@interface FBFileWriter_Null : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Sync : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Async : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

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

+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncDispatchDataWriterWithFileHandle:(NSFileHandle *)fileHandle
{
  NSError *error = nil;
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:self.createWorkQueue];
  if (![writer startReadingWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:writer];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)nullWriter
{
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:[[FBFileWriter_Null alloc] init]];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterWithFileHandle:(NSFileHandle *)fileHandle
{
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:[[FBFileWriter_Sync alloc] initWithFileHandle:fileHandle]];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileHandle:(NSFileHandle *)fileHandle queue:(dispatch_queue_t)queue error:(NSError **)error
{
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileHandle:fileHandle writeQueue:queue];
  if (![writer startReadingWithError:error]) {
    return nil;
  }
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:writer];
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
      return [FBFuture futureWithResult:[FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:writer]];
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

- (void)consumeData:(dispatch_data_t)data
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

- (void)consumeData:(dispatch_data_t)data
{
  [self.fileHandle writeData:[FBDataConsumerAdaptor adaptDispatchData:data]];
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

- (void)consumeData:(dispatch_data_t)data
{
  NSParameterAssert(self.io);

  dispatch_io_write(self.io, 0, data, self.writeQueue, ^(bool done, dispatch_data_t remainder, int error) {});
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
  // Having a self -> IO -> self cycle shouldn't be a problem in theory, since the cleanup handler should get when IO is done.
  // However, it appears that having the cycle in place here means that the cleanup handler is *never* called in the following circumstance:
  // 1) Pipe of FD14 is created.
  // 2) A writer is created for this pipe
  // 3) Data is written to this writer
  // 4) `consumeEndOfFile` is called and subsequently dispatch_io_close.
  // 5) The cleanup handler is called and subsequently the FD closed and IO channel disposed of via nil-ification.
  // 6) Pipe FD14 is torn down.
  // 7) A new Pipe resolving to FD14 is created.
  // 8) Data is written to this writer
  // 9) `consumeEndOfFile` is called and subsequently dispatch_io_close.
  // 10) The cleanup handler is *never* called and the FD is therefore never closed.
  // This isn't a problem in practice if different FDs are splayed, but repeating FDs representing different dispatch channels will cause this problem.
  __weak typeof(self) weakSelf = self;
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, self.fileHandle.fileDescriptor, self.writeQueue, ^(int errorCode) {
    [weakSelf ioChannelDidCloseWithError:errorCode];
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", self.fileHandle.fileDescriptor]
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
