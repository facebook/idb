/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileReader.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

static NSString *StateStringFromState(FBFileReaderState state)
{
  switch (state) {
    case FBFileReaderStateNotStarted:
      return @"Not Started";
    case FBFileReaderStateReading:
      return @"Reading";
    case FBFileReaderStateFinishedReadingNormally:
      return @"Finished Reading Normally";
    case FBFileReaderStateFinishedReadingInError:
      return @"Finished Reading in Error";
    case FBFileReaderStateFinishedReadingByCancellation:
      return @"Finished Reading in Cancellation";
    default:
      return @"Unknown";
  }
}

@interface FBFileReader ()

@property (nonatomic, copy, readonly) NSString *targeting;
@property (nonatomic, strong, readonly) id<FBDispatchDataConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *ioChannelFinishedReadOperation;
@property (nonatomic, assign, readonly) int fileDescriptor;
@property (nonatomic, assign, readonly) BOOL closeOnEndOfFile;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

@property (atomic, assign, readwrite) FBFileReaderState state;
@property (nonatomic, strong, nullable, readwrite) dispatch_io_t io;

@end

@implementation FBFileReader

#pragma mark Initializers

+ (dispatch_queue_t)createQueue
{
  return dispatch_queue_create("com.facebook.fbcontrolcore.fbfilereader", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)readerWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  return [self dispatchDataReaderWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile consumer:[FBDataConsumerAdaptor dispatchDataConsumerForDataConsumer:consumer] logger:logger];
}

+ (instancetype)dispatchDataReaderWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile consumer:(id<FBDispatchDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  NSString *targeting = [NSString stringWithFormat:@"fd %d", fileDescriptor];
  return [[self alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:closeOnEndOfFile consumer:consumer targeting:targeting queue:self.createQueue logger:logger];
}

+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = self.createQueue;
  return [FBFuture onQueue:queue resolveValue:^(NSError **error) {
    int fileDescriptor = open(filePath.UTF8String, O_RDONLY);
    if (fileDescriptor == -1) {
      return [[FBControlCoreError
        describeFormat:@"open of %@ returned an error '%s'", filePath, strerror(errno)]
        fail:error];
    }
    return [[self alloc] initWithFileDescriptor:fileDescriptor closeOnEndOfFile:YES consumer:[FBDataConsumerAdaptor dispatchDataConsumerForDataConsumer:consumer] targeting:filePath queue:queue logger:logger];
  }];
}

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile consumer:(id<FBDispatchDataConsumer>)consumer targeting:(NSString *)targeting queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileDescriptor = fileDescriptor;
  _consumer = consumer;
  _targeting = targeting;
  _readQueue = queue;
  _ioChannelFinishedReadOperation = [FBMutableFuture futureWithNameFormat:@"IO Channel Read of %@", targeting];
  _logger = logger;
  _state = FBFileReaderStateNotStarted;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Reader for %@ with state %@", self.targeting, StateStringFromState(self.state)];
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startReading
{
  return [FBFuture onQueue:self.readQueue resolve:^{
    return [self startReadingNow];
  }];
}

- (FBFuture<NSNumber *> *)stopReading
{
  return [FBFuture onQueue:self.readQueue resolve:^{
    return [self stopReadingNow];
  }];
}

- (FBFuture<NSNumber *> *)finishedReadingWithTimeout:(NSTimeInterval)timeout
{
  return [[[self
    finishedReading]
    timeout:timeout waitingFor:@"Process Reading to Finish"]
    onQueue:self.readQueue handleError:^(NSError *_) {
      // Since waiting for finishedReading timed out, we need to cancel the in-flight read operation.
      // This is not mandatory if finishedReading has resolved, which is why we use handleError.
      return [self stopReadingNow];
    }];
}

- (FBFuture<NSNumber *> *)finishedReading
{
  // We don't re-alias ioChannelFinishedReadOperation as if it's externally cancelled, we want the ioChannelFinishedReadOperation to resolve normally
  return [[[FBMutableFuture
    futureWithNameFormat:@"Finished reading of %@", self.targeting]
    resolveFromFuture:self.ioChannelFinishedReadOperation]
    onQueue:self.readQueue respondToCancellation:^{
      return [self stopReadingNow];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startReadingNow
{
  if (self.state != FBFileReaderStateNotStarted) {
    return [[FBControlCoreError
      describeFormat:@"Could not start reading read of %@ when it is in state %@", self.targeting, StateStringFromState(self.state)]
      failFuture];
  }
  NSAssert(!self.io, @"IO Channel should not exist when not started");

  // Get locals to be captured by the read, rather than self.
  int fileDescriptor = self.fileDescriptor;
  id<FBDispatchDataConsumer> consumer = self.consumer;
  __block int readErrorCode = 0;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  // This does not include any error during the read, which instead comes from the dispatch_io_read callback.
  // The self-capture is intentional, if the creator of an FBFileReader no longer strongly references self, we still need to keep it alive.
  // The self-capture is then removed in the below callback, which means the FBFileReader can then be deallocated.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileDescriptor, self.readQueue, ^(int createErrorCode) {
    [self ioChannelControlHasRelinquished:fileDescriptor withErrorCode:(createErrorCode ?: readErrorCode)];
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for %@", self.description]
      failFuture];
  }

  // Report partial results with as little as 1 byte read.
  dispatch_io_set_low_water(self.io, 1);
  dispatch_io_read(self.io, 0, SIZE_MAX, self.readQueue, ^(bool done, dispatch_data_t dispatchData, int errorCode) {
    if (dispatchData != NULL) {
      [consumer consumeData:dispatchData];
    }
    if (done) {
      readErrorCode = errorCode;
      [self ioChannelHasFinishedReadOperation:fileDescriptor withErrorCode:errorCode];
    }
  });
  self.state = FBFileReaderStateReading;
  return FBFuture.empty;
}

- (FBFuture<NSNumber *> *)stopReadingNow
{
  // The only error condition is that we haven't yet started reading
  if (self.state == FBFileReaderStateNotStarted) {
    return [[FBControlCoreError
      describeFormat:@"File reader has not started reading %@, you should call 'startReading' first", self.targeting]
      failFuture];
  }
  // All states other than reading mean that we don't need to close the channel.
  if (self.state != FBFileReaderStateReading) {
    return self.ioChannelFinishedReadOperation;
  }

  // dispatch_io_close will stop future reads of the io channel.
  // However, it does not mean that the dispatch_io_read callback will recieve further calls.
  // The true arbiter of whether we have reached the end of a read operation is 'done' being set in dispatch_io_read.
  // Therefore, closing the channel will have the effect that dispatch_io_read will become 'done' in the near future.
  // The ioChannelFinishedReadOperation future will then be resolved, so we can return that future from here.
  dispatch_io_close(self.io, DISPATCH_IO_STOP);
  return self.ioChannelFinishedReadOperation;
}

- (FBFuture<NSNumber *> *)ioChannelHasFinishedReadOperation:(int)fileDescriptor withErrorCode:(int)errorCode
{
  // This should only be called in response to the 'done' flagging on dispatch_io_read and not after calling dispatch_io_close.
  // "If the DISPATCH_IO_STOP option is specified in the flags parameter, the system attempts to interrupt any outstanding read and write operations on the I/O channel.
  //  Even if you specify this flag, the corresponding handlers may be invoked with partial results.
  //  In addition, the final invocation of the handler is passed the ECANCELED error code to indicate that the operation was interrupted."
  // This means that we can't assume that the dispatch_io_close will result in no more data to be delivered to dispatch_io_read and therefore the consumer.
  // We should also short circuit if we're not at a terminal state.
  if (self.state != FBFileReaderStateReading) {
    return self.ioChannelFinishedReadOperation;
  }
  switch (errorCode) {
    case 0:
      self.state = FBFileReaderStateFinishedReadingNormally;
      break;
    case ECANCELED:
      self.state = FBFileReaderStateFinishedReadingByCancellation;
      break;
    default:
      self.state = FBFileReaderStateFinishedReadingInError;
      break;
  }
  // Closing is not essential here as dispatch_io_close only marks the IO channel to prevent futher dispatch_io operations.
  // "After calling this function, you should not schedule any more read or write operations on the channel. Doing so causes an error to be sent to your handler".
  // However, this does enforce the invariant that future operations on the channel should fail.
  dispatch_io_close(self.io, 0);
  [self.ioChannelFinishedReadOperation resolveWithResult:@(errorCode)];
  [self.consumer consumeEndOfFile];
  return [[FBFuture futureWithResult:@(errorCode)] named:self.ioChannelFinishedReadOperation.name];
}

- (void)ioChannelControlHasRelinquished:(int)fileDescriptor withErrorCode:(int)errorCode
{
  NSAssert(self.io, @"Should only be called if an IO channel is present");
  // In the case of a bad file descriptor (EBADF) this may be called before we're done.
  // In that case, make sure we do the first-stage of tear-down.
  if (self.state == FBFileReaderStateReading) {
    [self ioChannelHasFinishedReadOperation:fileDescriptor withErrorCode:errorCode];
  }
  // Now that the IO channel is done for good, we can finally remove the reference to it.
  // By this point all read operations have finished and the consumer has been notified of an end-of-file.
  self.io = nil;

  // We can also now safely close the file descriptor if requested
  if (self.closeOnEndOfFile) {
    close(self.fileDescriptor);
  }
}

@end
