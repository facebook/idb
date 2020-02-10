/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileWriter.h"

#import "FBControlCoreError.h"

@interface FBFileWriter ()

@property (nonatomic, assign, readonly) int fileDescriptor;
@property (nonatomic, assign, readonly) BOOL closeOnEndOfFile;

@property (nonatomic, strong, readwrite) FBMutableFuture<NSNull *> *finishedConsumingMutable;

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile;

@end

@interface FBFileWriter_Null : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Sync : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

@end

@interface FBFileWriter_Async : FBFileWriter <FBDispatchDataConsumer, FBDataConsumerLifecycle>

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readwrite) dispatch_io_t io;

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile writeQueue:(dispatch_queue_t)writeQueue;

- (BOOL)startReadingWithError:(NSError **)error;

@end

@implementation FBFileWriter

#pragma mark Initializers

+ (dispatch_queue_t)createWorkQueue
{
  return dispatch_queue_create("com.facebook.fbcontrolcore.fbfilewriter", DISPATCH_QUEUE_SERIAL);;
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)nullWriter
{
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:[[FBFileWriter_Null alloc] init]];
}

+ (int)fileDescriptorForPath:(NSString *)filePath error:(NSError **)error
{
  int fileDescriptor = open(filePath.UTF8String, O_WRONLY | O_CREAT, 0644);
  if (!fileDescriptor) {
    return [[FBControlCoreError
      describeFormat:@"A file handle for path %@ could not be opened: %s", filePath, strerror(errno)]
      failInt:error];
  }
  return fileDescriptor;
}

+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncDispatchDataWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile
{
  NSError *error = nil;
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile writeQueue:self.createWorkQueue];
  if (![writer startReadingWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:writer];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile
{
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:[[FBFileWriter_Sync alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile]];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile queue:(dispatch_queue_t)queue error:(NSError **)error
{
  FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile writeQueue:queue];
  if (![writer startReadingWithError:error]) {
    return nil;
  }
  return [FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:writer];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asyncWriterWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile error:(NSError **)error
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [self asyncWriterWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile queue:queue error:error];
}

+ (id<FBDataConsumer, FBDataConsumerLifecycle>)syncWriterForFilePath:(NSString *)filePath error:(NSError **)error
{
  int fileDescriptor = [self fileDescriptorForPath:filePath error:error];
  if (!fileDescriptor) {
    return nil;
  }
  return [FBFileWriter syncWriterWithFileDescriptor:fileDescriptor closeOnEndOfFile:YES];
}

+ (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)asyncWriterForFilePath:(NSString *)filePath
{
  dispatch_queue_t queue = self.createWorkQueue;
  return [FBFuture
    onQueue:queue resolve:^() {
      NSError *error = nil;
      int fileDescriptor = [self fileDescriptorForPath:filePath error:&error];
      if (!fileDescriptor) {
        return [FBFuture futureWithError:error];
      }
      FBFileWriter_Async *writer = [[FBFileWriter_Async alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:YES writeQueue:queue];
      if (![writer startReadingWithError:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:[FBDataConsumerAdaptor dataConsumerForDispatchDataConsumer:writer]];
    }];
}

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileDescriptor = fileDescriptor;
  _closeOnEndOfFile = closeOnEndOfFile;
  _finishedConsumingMutable = [FBMutableFuture futureWithName:@"EOF Received"];

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
  [self.finishedConsumingMutable resolveWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingMutable;
}

@end

@implementation FBFileWriter_Sync

#pragma mark FBDataConsumer

- (void)consumeData:(dispatch_data_t)data
{
  dispatch_data_apply(data, ^ bool (dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
    write(self.fileDescriptor, buffer, size);
    return true;
  });
}

- (void)consumeEndOfFile
{
  [self.finishedConsumingMutable resolveWithResult:NSNull.null];
  if (self.closeOnEndOfFile) {
    close(self.fileDescriptor);
  }
}

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingMutable;
}

@end

@implementation FBFileWriter_Async

#pragma mark Initializers

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super initWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile];
  if (!self) {
    return nil;
  }

  _writeQueue = writeQueue;

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(dispatch_data_t)data
{
  dispatch_io_t io = self.io;
  if (!io) {
    return;
  }

  dispatch_io_write(io, 0, data, self.writeQueue, ^(bool done, dispatch_data_t remainder, int error) {});
}

- (void)consumeEndOfFile
{
  dispatch_io_t io = self.io;
  if (!io) {
    return;
  }

  // We can't close the file handle right now since there may still be pending IO operations on the channel.
  // The safe place to do this is within the dispatch_io_create cleanup_handler callback.
  // Until the cleanup_handler is called, libdispatch takes over control of the file descriptor.
  // We also want to ensure that there are no pending write operations on the channel, otherwise it's easy to miss data.
  // The barrier ensures that there are no pending writes before we attempt to interrupt the channel.
  dispatch_io_barrier(io, ^{
    dispatch_io_close(io, DISPATCH_IO_STOP);
  });
}

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingMutable;
}

#pragma mark Private

- (BOOL)startReadingWithError:(NSError **)error
{
  NSParameterAssert(!self.io);

  FBMutableFuture<NSNull *> *finishedConsuming = self.finishedConsumingMutable;

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
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, self.fileDescriptor, self.writeQueue, ^(int errorCode) {
    [weakSelf ioChannelDidCloseWithError:errorCode];

    // Since writing is asynchronous, we don't want to vend futures that show that all work on a file descriptor has finished.
    // Instead we should wait until the io channel is fully closed, this only occurs in this callback.
    [finishedConsuming resolveWithResult:NSNull.null];
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", self.fileDescriptor]
      failBool:error];
  }

  // Report partial results with as little as 1 byte read.
  dispatch_io_set_low_water(self.io, 1);
  return YES;
}

- (void)ioChannelDidCloseWithError:(int)errorCode
{
  self.io = nil;
  if (self.closeOnEndOfFile) {
    close(self.fileDescriptor);
  }
}

@end
