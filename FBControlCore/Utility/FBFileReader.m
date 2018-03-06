// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileReader.h"

#import "FBControlCoreError.h"

@interface FBFileReader ()

@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;
@property (nonatomic, copy, readonly) NSString *targeting;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *readingHasEnded;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *stopped;

@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;
@property (nonatomic, strong, nullable, readwrite) dispatch_io_t io;

@end

@implementation FBFileReader

#pragma mark Initializers

+ (dispatch_queue_t)createQueue
{
  return dispatch_queue_create("com.facebook.fbxctest.multifilereader", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer
{
  NSString *targeting = [NSString stringWithFormat:@"fd %d", fileHandle.fileDescriptor];
  return [[self alloc] initWithFileHandle:fileHandle consumer:consumer targeting:targeting queue:self.createQueue];
}

+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer
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
    return [[self alloc] initWithFileHandle:fileHandle consumer:consumer targeting:filePath queue:queue];
  }];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer targeting:(NSString *)targeting queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }
  __weak typeof(self) weakSelf = self;

  _fileHandle = fileHandle;
  _consumer = consumer;
  _targeting = targeting;
  _readQueue = queue;
  _readingHasEnded = FBMutableFuture.future;
  _stopped = [_readingHasEnded onQueue:_readQueue chain:^(FBFuture *future) {
    [consumer consumeEndOfFile];
    weakSelf.fileHandle = nil;
    return future;
  }];

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Reader for %@ with state %@", self.targeting, self.readingHasEnded];
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)completed
{
  return [self.stopped onQueue:self.readQueue respondToCancellation:^{
    return [self stopReading];
  }];
}

- (FBFuture<NSNull *> *)startReading
{
  return [FBFuture onQueue:self.readQueue resolve:^{
    return [self startReadingNow];
  }];
}

- (FBFuture<NSNull *> *)stopReading
{
  return [FBFuture onQueue:self.readQueue resolve:^{
    return [self stopReadingNow];
  }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startReadingNow
{
  if (self.io) {
    return [[FBControlCoreError
      describeFormat:@"Could not start reading read of %@ has started", self.fileHandle]
      failFuture];
  }

  // Get locals to be captured by the read, rather than self.
  NSFileHandle *fileHandle = self.fileHandle;
  id<FBFileConsumer> consumer = self.consumer;
  FBMutableFuture<NSNull *> *readingHasEnded = self.readingHasEnded;
  NSString *targeting = self.targeting;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.readQueue, ^(int errorCode) {
    [FBFileReader resolveReading:readingHasEnded withCode:errorCode targeting:targeting];
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", fileHandle.fileDescriptor]
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
    if (done) {
      [FBFileReader resolveReading:readingHasEnded withCode:errorCode targeting:targeting];
    }
  });
  return [FBFuture futureWithResult:NSNull.null];
}

- (FBFuture<NSNull *> *)stopReadingNow
{
  // Return early if we've already stopped.
  if (!self.io) {
    return [[FBControlCoreError
      describe:@"File Handle is not open for reading, you should call 'startReading' first"]
      failFuture];
  }

  // Return the future after dispatching to the main queue.
  dispatch_io_close(self.io, DISPATCH_IO_STOP);
  self.io = nil;

  return self.stopped;
}

+ (void)resolveReading:(FBMutableFuture<NSNull *> *)readingHasEnded withCode:(int)errorCode targeting:(NSString *)targeting
{
  // Everything completed normally, or ended
  if (errorCode == 0 || errorCode == ECANCELED) {
    [readingHasEnded resolveWithResult:NSNull.null];
  } else {
    NSError *error = [[FBControlCoreError describeFormat:@"IO Channel %@ closed with error code %d", targeting, errorCode] build];
    [readingHasEnded resolveWithError:error];
  }
}

@end
