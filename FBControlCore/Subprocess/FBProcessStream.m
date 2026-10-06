/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessStream.h"

#import <fcntl.h>
#import <sys/stat.h>
#import <sys/types.h>

#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"

#pragma mark FBProcessStreamAttachment

@implementation FBProcessStreamAttachment

- (instancetype)initWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile mode:(FBProcessStreamAttachmentMode)mode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileDescriptor = fileDescriptor;
  _closeOnEndOfFile = closeOnEndOfFile;
  _mode = mode;

  return self;
}

- (void)close
{
  if (self.fileDescriptor) {
    close(self.fileDescriptor);
  }
}

@end

@interface FBProcessInput ()

@property (nonatomic, readonly, strong) dispatch_queue_t workQueue;
@property (nonatomic, readwrite, assign) int readEnd;
@property (nonatomic, readwrite, assign) int writeEnd;

@end

@interface FBProcessInput_Consumer : FBProcessInput <DataConsumer>

@property (nullable, nonatomic, readwrite, strong) id<DataConsumer> writer;
// What is consumed before the pipe exists, delivered once it is attached. Guarded by @synchronized(self), as is `writer`.
@property (nullable, nonatomic, readwrite, strong) NSMutableData *pendingData;
@property (nonatomic, readwrite, assign) BOOL pendingEndOfFile;
// Once detached no attach follows, so later writes are dropped rather than held for one.
@property (nonatomic, readwrite, assign) BOOL detached;

@end

@interface FBProcessInput_Data : FBProcessInput_Consumer

- (instancetype)initWithData:(NSData *)data;

@property (nonatomic, readonly, strong) NSData *data;

@end

@class NSOutputStream_FBProcessInput;

@interface FBProcessInput_InputStream : FBProcessInput <StandardStreamTransfer>

@property (nonatomic, readonly, strong) NSOutputStream_FBProcessInput *stream;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNumber *> *writeFuture;

@end

@interface NSOutputStream_FBProcessInput : NSOutputStream

@property (nonatomic, readonly, strong) FBFuture<NSNumber *> *writeFuture;
@property (nonatomic, readwrite, assign) int fileDescriptor;
@property (atomic, readwrite, assign) ssize_t bytesWritten;
@property (nullable, atomic, readwrite, copy) NSString *errorMessage;
@property (atomic, readwrite, assign) NSStreamStatus status;

- (instancetype)initWithWriteFuture:(FBFuture<NSNumber *> *)writeFuture;

@end

@implementation FBProcessInput

#pragma mark Initializers

+ (FBProcessInput<id<DataConsumer>> *)inputFromConsumer
{
  return [[FBProcessInput_Consumer alloc] init];
}

+ (FBProcessInput<NSOutputStream *> *)inputFromStream
{
  return [[FBProcessInput_InputStream alloc] init];
}

+ (FBProcessInput<NSData *> *)inputFromData:(NSData *)data
{
  return [[FBProcessInput_Data alloc] initWithData:data];
}

- (instancetype)init
{
  return [self initWithWorkQueue:dispatch_queue_create("com.facebook.fbcontrolcore.process_stream", DISPATCH_QUEUE_SERIAL)];
}

- (instancetype)initWithWorkQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _workQueue = workQueue;

  return self;
}

#pragma mark StandardStream

- (FBFuture<FBProcessStreamAttachment *> *)attach
{
  return [[FBFuture
           onQueue:self.workQueue
           resolve:^{
             if (self.readEnd || self.writeEnd) {
               return (FBFuture *)[[ControlCoreError
                                    describe:@"Cannot Attach Twice"]
                                   failFuture];
             }

             int fileDescriptors[2] = {0, 0};
             if (pipe(fileDescriptors) != 0) {
               return (FBFuture *)[[ControlCoreError
                                    describe:[NSString stringWithFormat:@"Failed to create a pipe: %s", strerror(errno)]]
                                   failFuture];
             }
             self.readEnd = fileDescriptors[0];
             self.writeEnd = fileDescriptors[1];

             // Pass out the read end as input to a process.
             // Subclases will write to the write end.
             return [FBFuture futureWithResult:[[FBProcessStreamAttachment alloc] initWithFileDescriptor:self.readEnd closeOnEndOfFile:YES mode:FBProcessStreamAttachmentModeInput]];
           }]
          named:[NSString stringWithFormat:@"Attach %@ to pipe", self.description]];
}

- (FBFuture<NSNull *> *)detach
{
  return [[FBFuture
           onQueue:self.workQueue
           resolve:^FBFuture<NSNull *> * {
             int readEnd = self.readEnd;
             if (!readEnd) {
               return (FBFuture *)[[ControlCoreError
                                    describe:[NSString stringWithFormat:@"Nothing is attached to %@", self]]
                                   failFuture];
             }

             // Close the read end of the descriptor since the input it no-longer consuming it
             // The writer is responsible for closing and referencing the write end.
             close(readEnd);
             self.readEnd = 0;
             self.writeEnd = 0;

             return FBFuture.empty;
           }]
          named:[NSString stringWithFormat:@"Detach %@", self.description]];
}

- (id<DataConsumer>)contents
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSError *)streamError
{
  return nil;
}

@end

@implementation FBProcessInput_Consumer

#pragma mark StandardStream

- (id<DataConsumer>)contents
{
  return self;
}

- (FBFuture<FBProcessStreamAttachment *> *)attach
{
  return [[[super
            attach]
           onQueue:self.workQueue
           fmap:^(FBProcessStreamAttachment *attachment) {
             NSError *error = nil;
             // Construct a writer to write to, on eof the file descriptor is closed and the reading continues on the other side of the pipe.
             // The read end is closed in the superclassess detach.
             id<DataConsumer> writer = [FileWriter asyncWriterWithFileDescriptor:self.writeEnd closeOnEndOfFile:YES error:&error];
             if (!writer) {
               return (FBFuture *)[[ControlCoreError
                                    describe:[NSString stringWithFormat:@"Failed to create a writer for pipe %@", error]]
                                   failFuture];
             }
             @synchronized(self) {
               self.writer = writer;
               self.detached = NO;
               NSData *pendingData = self.pendingData;
               if (pendingData) {
                 [writer consumeData:pendingData];
                 self.pendingData = nil;
               }
               if (self.pendingEndOfFile) {
                 [writer consumeEndOfFile];
               }
             }
             return [FBFuture futureWithResult:attachment];
           }]
          named:[NSString stringWithFormat:@"Attach %@ to pipe", self.description]];
}

- (FBFuture<NSNull *> *)detach
{
  return [[[super
            detach]
           onQueue:self.workQueue
           notifyOfCompletion:^(id _) {
             @synchronized(self) {
               self.writer = nil;
               self.detached = YES;
               self.pendingData = nil;
               self.pendingEndOfFile = NO;
             }
           }]
          named:[NSString stringWithFormat:@"Detach %@", self.description]];
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized(self) {
    if (self.writer) {
      [self.writer consumeData:data];
      return;
    }
    if (self.detached) {
      return;
    }
    if (!self.pendingData) {
      self.pendingData = [NSMutableData data];
    }
    [self.pendingData appendData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized(self) {
    if (self.writer) {
      [self.writer consumeEndOfFile];
      return;
    }
    if (self.detached) {
      return;
    }
    self.pendingEndOfFile = YES;
  }
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Input to consumer";
}

@end

@implementation FBProcessInput_Data

#pragma mark Initializers

- (instancetype)initWithData:(NSData *)data
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _data = data;

  return self;
}

#pragma mark StandardStream

- (FBFuture<FBProcessStreamAttachment *> *)attach
{
  return [[[super
            attach]
           onQueue:self.workQueue
           map:^(FBProcessStreamAttachment *attachment) {
             [self.writer consumeData:self.data];
             [self.writer consumeEndOfFile];
             return attachment;
           }]
          named:[NSString stringWithFormat:@"Attach %@ to pipe", self.description]];
}

- (NSData *)contents
{
  return self.data;
}

#pragma mark NSObject

- (NSString *)description
{
  return @"Input to Data";
}

@end

@implementation FBProcessInput_InputStream

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writeFuture = FBMutableFuture.future;
  _stream = [[NSOutputStream_FBProcessInput alloc] initWithWriteFuture:_writeFuture];

  return self;
}

#pragma mark StandardStream

- (NSOutputStream *)contents
{
  return self.stream;
}

- (FBFuture<FBProcessStreamAttachment *> *)attach
{
  return [[super
           attach]
          onQueue:self.workQueue
          map:^(FBProcessStreamAttachment *attachment) {
            [self.writeFuture resolveWithResult:@(self.writeEnd)];
            return attachment;
          }];
}

- (NSString *)description
{
  return @"Input to NSOutputStream";
}

#pragma mark StandardStreamTransfer

- (ssize_t)bytesTransferred
{
  return self.stream.bytesWritten;
}

- (NSError *)streamError
{
  return self.stream.streamError;
}

@end

@implementation NSOutputStream_FBProcessInput

#pragma mark Initializers

- (instancetype)initWithWriteFuture:(FBFuture<NSNumber *> *)writeFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  // The pipe first has to be created, so we don't know this ahead of time.
  // Instead we block until the write descriptor becomes available.
  _writeFuture = writeFuture;
  _fileDescriptor = 0;
  _bytesWritten = 0;
  _errorMessage = nil;
  _status = NSStreamStatusNotOpen;

  return self;
}

#pragma mark NSOutputStream

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
  int fileDescriptor = self.fileDescriptor;
  if (!fileDescriptor) {
    NSStreamStatus status = self.status;
    if (status == NSStreamStatusNotOpen) {
      [self resolveError:@"Pipe for writing is not open"];
    } else if (status == NSStreamStatusClosed) {
      [self resolveError:@"Pipe for writing is closed"];
    } else {
      [self resolveError:@"Pipe for writing is does not exist"];
    }
    return -1;
  }
  self.status = NSStreamStatusWriting;
  NSUInteger totalWritten = 0;
  while (totalWritten < len) {
    ssize_t result = write(self.fileDescriptor, buffer + totalWritten, len - totalWritten);
    if (result == -1 && errno == EINTR) {
      continue;
    }
    if (result <= 0) {
      [self resolveError:[[NSString alloc] initWithCString:strerror(errno) encoding:NSASCIIStringEncoding]];
      return -1;
    }
    totalWritten += (NSUInteger)result;
  }
  self.status = NSStreamStatusOpen;
  self.bytesWritten += (ssize_t)totalWritten;
  return (NSInteger)totalWritten;
}

- (void)open
{
  if (self.streamStatus != NSStreamStatusNotOpen) {
    [self resolveError:[NSString stringWithFormat:@"Stream status is not NSStreamStatusNotOpen is %lu", self.streamStatus]];
    return;
  }
  self.status = NSStreamStatusOpening;
  NSNumber *fileDescriptor = [self.writeFuture block:nil];
  self.fileDescriptor = fileDescriptor.intValue;
  if (fcntl(self.fileDescriptor, F_SETNOSIGPIPE, 1) == -1) {
    [self resolveError:[[NSString alloc] initWithCString:strerror(errno) encoding:NSASCIIStringEncoding]];
    return;
  }
  self.status = NSStreamStatusOpen;
}

- (void)close
{
  if (self.fileDescriptor) {
    close(self.fileDescriptor);
    self.fileDescriptor = 0;
    self.status = NSStreamStatusClosed;
  }
}

- (BOOL)hasSpaceAvailable
{
  return YES;
}

- (NSError *)streamError
{
  NSString *errorMessage = self.errorMessage;
  if (!errorMessage) {
    return nil;
  }
  return [[ControlCoreError
           describe:errorMessage]
          build];
}

- (NSStreamStatus)streamStatus
{
  return self.status;
}

#pragma mark Private

- (void)resolveError:(NSString *)errorMessage
{
  if (self.errorMessage) {
    return;
  }
  self.errorMessage = errorMessage;
  self.status = NSStreamStatusError;
}

@end
