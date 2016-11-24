// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileReader.h"

#import "FBControlCoreError.h"

@interface FBFileReader ()

@property (nonatomic, strong, readonly) id<FBFileDataConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t readQueue;

@property (nonatomic, strong, nullable, readwrite) NSFileHandle *fileHandle;
@property (nonatomic, strong, nullable, readwrite) dispatch_io_t io;
@property (atomic, assign, readwrite) int errorCode;

@end

@implementation FBFileReader

+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileDataConsumer>)consumer
{
  return [[self alloc] initWithFileHandle:fileHandle consumer:consumer];
}

+ (nullable instancetype)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileDataConsumer>)consumer error:(NSError **)error
{
  NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:filePath];
  if (!handle) {
    return [[FBControlCoreError describeFormat:@"Failed to open file for reading: %@", filePath] fail:error];
  }
  return [self readerWithFileHandle:handle consumer:consumer];
}

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileDataConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _errorCode = 0;
  _fileHandle = fileHandle;
  _consumer = consumer;
  _readQueue = dispatch_queue_create("com.facebook.fbxctest.multifilereader", DISPATCH_QUEUE_SERIAL);

  return self;
}

- (BOOL)startReadingWithError:(NSError **)error
{
  NSParameterAssert(self.io == NULL);

  NSFileHandle *fileHandle = self.fileHandle;
  id<FBFileDataConsumer> consumer = self.consumer;

  // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
  self.io = dispatch_io_create(DISPATCH_IO_STREAM, fileHandle.fileDescriptor, self.readQueue, ^(int errorCode) {
    self.errorCode = errorCode;
  });
  if (!self.io) {
    return [[FBControlCoreError
      describeFormat:@"A IO Channel could not be created for fd %d", fileHandle.fileDescriptor]
      failBool:error];
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
      self.errorCode = errorCode;
    }
    if (done) {
      [consumer consumeEndOfFile];
    }
  });
  return YES;
}

- (BOOL)stopReadingWithError:(NSError **)error
{
  // Return early if the resources are gone, or already being teared down.
  if (self.errorCode) {
    return [[FBControlCoreError
      describeFormat:@"File reading for file descriptor %d terminated with error code %d", self.fileHandle.fileDescriptor, self.errorCode]
      failBool:error];
  }
  if (!self.io) {
    return [[FBControlCoreError
      describe:@"File Handle is not open for reading, you should call 'startReading' first"]
      failBool:error];
  }

  // Remove resources form self to be closed in the io barrier.
  NSFileHandle *fileHandle = self.fileHandle;
  self.fileHandle = nil;
  dispatch_io_t io = self.io;
  self.io = nil;

  // Wait for all io operations to stop with a barrier, then close the io channel
  dispatch_io_barrier(io, ^{
    dispatch_io_close(io, DISPATCH_IO_STOP);
    [fileHandle closeFile];
  });
  return YES;
}

@end
