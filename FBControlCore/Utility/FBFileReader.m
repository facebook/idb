// Copyright 2004-present Facebook. All Rights Reserved.

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
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *ioChannelFinishedReadOperation;
@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;
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

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  NSString *targeting = [NSString stringWithFormat:@"fd %d", fileHandle.fileDescriptor];
  return [[self alloc] initWithFileHandle:fileHandle consumer:consumer targeting:targeting queue:self.createQueue logger:logger];
}

+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = self.createQueue;
  return [FBFuture onQueue:queue resolveValue:^(NSError **error) {
    int fileDescriptor = open(filePath.UTF8String, O_RDONLY);
    if (fileDescriptor == -1) {
      return [[FBControlCoreError
        describeFormat:@"open of %@ returned an error %d", filePath, errno]
        fail:error];
    }
    NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:fileDescriptor closeOnDealloc:YES];
    return [[self alloc] initWithFileHandle:fileHandle consumer:consumer targeting:filePath queue:queue logger:logger];
  }];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBDataConsumer>)consumer targeting:(NSString *)targeting queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
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
  NSFileHandle *fileHandle = self.fileHandle;
  id<FBDataConsumer> consumer = self.consumer;
  __block int readErrorCode = 0;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  // This does not include any error during the read, which instead comes from the dispatch_io_read callback.
  // The self-capture is intentional, if the creator of an FBFileReader no longer strongly references self, we still need to keep it alive.
  // The self-capture is then removed in the below callback, which means the FBFileReader can then be deallocated.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.readQueue, ^(int createErrorCode) {
    [self ioChannelControlHasRelinquished:fileHandle withErrorCode:(createErrorCode ?: readErrorCode)];
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
      // One-way bridging of dispatch_data_t to NSData is permitted.
      // Since we can't safely assume all consumers of the NSData work discontiguous ranges, we have to make the dispatch_data contiguous.
      // This is done with dispatch_data_create_map, which is 0-copy for a contiguous range but copies for non-contiguous ranges.
      // https://twitter.com/catfish_man/status/393032222808100864
      // https://developer.apple.com/library/archive/releasenotes/Foundation/RN-Foundation-older-but-post-10.8/
      NSData *data = (NSData *) dispatch_data_create_map(dispatchData, NULL, NULL);
      [consumer consumeData:data];
    }
    if (done) {
      readErrorCode = errorCode;
      [self ioChannelHasFinishedReadOperation:fileHandle withErrorCode:errorCode];
    }
  });
  self.state = FBFileReaderStateReading;
  return [FBFuture futureWithResult:NSNull.null];
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

  // Return the future after dispatching to the main queue.
  // Cleanup of the IO Channel happens in the dispatch_io_create callback;
  return [self ioChannelHasFinishedReadOperation:self.fileHandle withErrorCode:ECANCELED];
}

- (FBFuture<NSNumber *> *)ioChannelHasFinishedReadOperation:(NSFileHandle *)fileHandle withErrorCode:(int)errorCode
{
  // This can be called through a manual stopping of reading, or reaching the eof.
  // Either way this should only execute once, so short circuit if it does.
  if (self.state != FBFileReaderStateReading) {
    return self.ioChannelFinishedReadOperation;
  }
  NSAssert(self.io, @"The IO Channel to close should be present");
  switch (errorCode) {
    case 0:
      self.state = FBFileReaderStateFinishedReadingNormally;
      dispatch_io_close(self.io, 0);
      break;
    case ECANCELED:
      self.state = FBFileReaderStateFinishedReadingByCancellation;
      dispatch_io_close(self.io, DISPATCH_IO_STOP);
      break;
    default:
      self.state = FBFileReaderStateFinishedReadingInError;
      dispatch_io_close(self.io, 0);
      break;
  }
  [self.ioChannelFinishedReadOperation resolveWithResult:@(errorCode)];
  return [[FBFuture futureWithResult:@(errorCode)] named:self.ioChannelFinishedReadOperation.name];
}

- (void)ioChannelControlHasRelinquished:(NSFileHandle *)fileHandle withErrorCode:(int)errorCode
{
  // In the case of a bad file descriptor (EBADF) this may be called before we're done.
  // In that case, make sure we do the first-stage of tear-down.
  if (self.state == FBFileReaderStateReading) {
    [self ioChannelHasFinishedReadOperation:fileHandle withErrorCode:errorCode];
  }
  // This should only be written once and only after all pending write operations have finished.
  // We can't run this after dispatch_io_close because, from the dispatch_io_stop docs
  // "If the DISPATCH_IO_STOP option is specified in the flags parameter, the system attempts to interrupt any outstanding read and write operations on the I/O channel.
  //  Even if you specify this flag, the corresponding handlers may be invoked with partial results.
  //  In addition, the final invocation of the handler is passed the ECANCELED error code to indicate that the operation was interrupted."
  // This means that we can't assume that the dispatch_io_stop will result in no more data to be delivered to the consumer.
  // This method is only called once, and at the end of *all* read operations.
  [self.consumer consumeEndOfFile];
  // Weneed to get rid of the IO Channel to release the cycles on self.
  self.io = nil;
}

@end
