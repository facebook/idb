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
    case FBFileReaderStateTerminating:
      return @"Terminating";
    case FBFileReaderStateTerminatedNormally:
      return @"Terminated Normally";
    case FBFileReaderStateTerminatedAbnormally:
      return @"Terminated Abnormally";
    default:
      return @"Unknown";
  }
}

@interface FBFileReader ()

@property (nonatomic, copy, readonly) NSString *targeting;
@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *readingHasEnded;
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *stopped;
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

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
{
  NSString *targeting = [NSString stringWithFormat:@"fd %d", fileHandle.fileDescriptor];
  return [[self alloc] initWithFileHandle:fileHandle consumer:consumer targeting:targeting queue:self.createQueue logger:logger];
}

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer
{
  return [self readerWithFileHandle:fileHandle consumer:consumer logger:nil];
}

+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger
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

+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer
{
  return [self readerWithFilePath:filePath consumer:consumer logger:nil];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer targeting:(NSString *)targeting queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _consumer = consumer;
  _targeting = targeting;
  _readQueue = queue;
  _readingHasEnded = FBMutableFuture.future;
  _logger = logger;
  _state = FBFileReaderStateNotStarted;
  _stopped = [_readingHasEnded onQueue:_readQueue chain:^(FBFuture *future) {
    [consumer consumeEndOfFile];
    return future;
  }];

  return self;
}

- (void)dealloc
{
  if (self.stopped.state == FBFutureStateRunning) {
    [self.logger.error log:@"FileReader is being deallocated before it has completed. please call detach or bad things can happen"];
  }
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

- (FBFuture<NSNumber *> *)completed
{
  return [self.stopped onQueue:self.readQueue respondToCancellation:^{
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
  id<FBFileConsumer> consumer = self.consumer;
  __block int readErrorCode = 0;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  // This does not include any error during the read, which instead comes from the dispatch_io_read callback.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.readQueue, ^(int createErrorCode) {
    [self resolveReadingWithCode:(createErrorCode ?: readErrorCode)];
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
      const void *buffer;
      size_t size;
      __unused dispatch_data_t map = dispatch_data_create_map(dispatchData, &buffer, &size);
      NSData *data = [NSData dataWithBytes:buffer length:size];
      [consumer consumeData:data];
    }
    if (errorCode) {
      readErrorCode = errorCode;
    }
  });
  self.state = FBFileReaderStateReading;
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNumber *> *)stopReadingNow
{
  // Return early if we've already stopped.
  if (self.state == FBFileReaderStateNotStarted) {
    return [[FBControlCoreError
      describeFormat:@"File reader has not started reading %@, you should call 'startReading' first", self.targeting]
      failFuture];
  }
  if (self.state != FBFileReaderStateReading) {
    return [[FBControlCoreError
      describeFormat:@"Stop Reading of %@ requested, but is in a terminal state of %@", self.targeting, StateStringFromState(self.state)]
      failFuture];
  }
  NSAssert(self.io, @"File Reader state is %@ but there's no IO Channel", StateStringFromState(self.state));

  // Return the future after dispatching to the main queue.
  // Cleanup of the IO Channel happens in the dispatch_io_create callback;
  dispatch_io_close(self.io, DISPATCH_IO_STOP);
  self.state = FBFileReaderStateTerminating;

  return self.stopped;
}

- (FBFuture<NSNumber *> *)resolveReadingWithCode:(int)errorCode
{
  // Everything completed normally, or ended so teardown the channel and notify
  self.io = nil;
  if (errorCode == 0 || errorCode == ECANCELED) {
    self.state = FBFileReaderStateTerminatedNormally;
    return [self.readingHasEnded resolveWithResult:@(FBFileReaderStateTerminatedNormally)];
  } else {
    self.state = FBFileReaderStateTerminatedAbnormally;
    NSError *error = [[FBControlCoreError describeFormat:@"IO Channel %@ closed with error code %d", self.description, errorCode] build];
    return [self.readingHasEnded resolveWithError:error];
  }
}

@end
