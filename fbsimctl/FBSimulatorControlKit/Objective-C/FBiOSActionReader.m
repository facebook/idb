/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSActionReader.h"

#import "FBUploadBuffer.h"
#import "FBiOSActionRouter.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeActionReader = @"action_reader";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBiOSActionReaderMediator : NSObject <FBSocketConsumer, FBiOSActionReaderDelegate>

@property (nonatomic, strong, readonly) FBiOSActionReader *reader;
@property (nonatomic, strong, readonly) FBiOSActionRouter *router;
@property (nonatomic, strong, readonly) id<FBiOSActionReaderDelegate> delegate;
@property (nonatomic, strong, readonly) id<FBDataConsumer> writeBack;
@property (nonatomic, strong, readonly) id<FBConsumableBuffer> lineBuffer;
@property (nonatomic, strong, readwrite, nullable) FBUploadBuffer *uploadBuffer;

@end

@implementation FBiOSActionReaderMediator

- (instancetype)initWithReader:(FBiOSActionReader *)reader router:(FBiOSActionRouter *)router delegate:(id<FBiOSActionReaderDelegate>)delegate writeBack:(id<FBDataConsumer>)writeBack
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reader = reader;
  _router = router;
  _delegate = delegate;
  _writeBack = writeBack;
  _lineBuffer = [FBDataBuffer consumableBuffer];
  _uploadBuffer = nil;

  return self;
}

#pragma mark FBSocketConsumer Implementation

- (void)writeBackAvailable:(id<FBDataConsumer>)writeBack
{
  _writeBack = writeBack;
}

#pragma mark FBDataConsumer Implementation

- (void)consumeData:(NSData *)data
{
  if (self.uploadBuffer) {
    NSData *remainder = nil;
    FBUploadedDestination *destination = [self.uploadBuffer writeData:data remainderOut:&remainder];
    if (destination) {
      [self dispatchUploadCompleted:destination];
    }
    data = remainder;
  }
  if (!data) {
    return;
  }
  [self.lineBuffer consumeData:data];
  [self runBuffer];
}

- (void)consumeEndOfFile
{
  _writeBack = FBFileWriter.nullWriter;
}

#pragma mark Private

- (dispatch_queue_t)actionQueue
{
  return self.router.target.workQueue;
}

- (void)runBuffer
{
  NSData *lineData = self.lineBuffer.consumeLineData;
  while (lineData) {
    [self dispatchLine:lineData];
    lineData = self.lineBuffer.consumeLineData;
  }
}

- (void)dispatchLine:(NSData *)line
{
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:line options:0 error:&error];
  if (!json) {
    [self dispatchParseError:line error:error];
    return;
  }

  id<FBiOSTargetFuture> action = [self.router actionFromJSON:json error:&error];
  if (!action) {
    [self dispatchParseError:line error:error];
    return;
  }
  if ([action isKindOfClass:FBUploadHeader.class]) {
    [self dispatchUploadStarted:(FBUploadHeader *)action];
    return;
  }
  [self dispatchAction:action];
}

- (void)dispatchAction:(id<FBiOSTargetFuture>)action
{
  FBiOSActionReader *reader = self.reader;
  id<FBiOSTarget> target = self.router.target;

  // Notify Delegate of the start of the Action.
  __block NSString *response = nil;
  dispatch_sync(self.actionQueue, ^{
    response = [self.delegate reader:reader willStartPerformingAction:action onTarget:target];
  });
  [self reportString:response];

  // Run the action, on the main queue
  __block NSError *error = nil;
  __block BOOL success = NO;
  dispatch_sync(self.actionQueue, ^{
    success = [[action runWithTarget:target consumer:self.writeBack reporter:self.reporter] await:&error] != nil;
  });

  // Notify the delegate that the reader has finished, report the resultant string.
  response = success
    ? [self.delegate reader:reader didProcessAction:action onTarget:target]
    : [self.delegate reader:reader didFailToProcessAction:action onTarget:target error:error];
  [self reportString:response];
}

- (void)dispatchUploadStarted:(FBUploadHeader *)header
{
  NSParameterAssert(self.uploadBuffer == nil);

  self.uploadBuffer = [FBUploadBuffer bufferWithHeader:header workingDirectory:self.router.target.auxillaryDirectory];
  __block NSString *response = nil;
  dispatch_sync(self.actionQueue, ^{
    response = [self.delegate reader:self.reader willStartReadingUpload:header];
  });
  [self reportString:response];

  // Push the buffer back through.
  NSData *remainder = [self.lineBuffer consumeCurrentData];
  [self consumeData:remainder];
}

- (void)dispatchUploadCompleted:(FBUploadedDestination *)destination
{
  NSParameterAssert(self.uploadBuffer != nil);

  self.uploadBuffer = nil;
  __block NSString *response = nil;
  dispatch_sync(self.actionQueue, ^{
    response = [self.delegate reader:self.reader didFinishUpload:destination];
  });
  [self reportString:response];
}

- (void)dispatchParseError:(NSData *)lineData error:(NSError *)error
{
  NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
  __block NSString *response = nil;
  dispatch_sync(self.actionQueue, ^{
    response = [self.delegate reader:self.reader failedToInterpretInput:line error:error];
  });
  if (!response) {
    return;
  }
  [self reportString:response];
}

- (void)reportString:(nullable NSString *)string
{
  if (!string) {
    return;
  }
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  [self.writeBack consumeData:data];
}

- (id<FBEventReporter>)reporter
{
  return [FBEventReporter reporterWithInterpreter:self.interpreter consumer:self.consumer];
}

- (id<FBEventInterpreter>)interpreter
{
  return self.delegate.interpreter;
}

- (id<FBDataConsumer>)consumer
{
  return self.delegate.consumer;
}

#pragma mark Forwarding

- (id)forwardingTargetForSelector:(SEL)selector
{
  if ([self.delegate respondsToSelector:selector]) {
    return self.delegate;
  }
  return [super forwardingTargetForSelector:selector];
}

@synthesize metadata;

@end

#pragma clang diagnostic push

@interface FBiOSActionSocket : FBiOSActionReader <FBSocketConnectionManagerDelegate>

@property (nonatomic, strong, nullable, readwrite) FBSocketConnectionManager *reader;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router port:(in_port_t)port;

@end

@interface FBiOSActionFileHandle : FBiOSActionReader <FBDataConsumer>

@property (nonatomic, strong, readonly) FBiOSActionReaderMediator *mediator;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> writer;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle;

@end

@interface FBiOSActionReader ()

@property (nonatomic, strong, nullable, readwrite) id<FBiOSActionReaderDelegate> delegate;
@property (nonatomic, strong, readonly) FBiOSActionRouter *router;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completedFuture;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router;

@end

@implementation FBiOSActionReader

#pragma mark Initializers

+ (instancetype)socketReaderForTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSActionReaderDelegate>)delegate port:(in_port_t)port
{
  FBiOSActionRouter *router = [FBiOSActionRouter routerForTarget:target];
  return [self socketReaderForRouter:router delegate:delegate port:port];
}

+ (instancetype)socketReaderForRouter:(FBiOSActionRouter *)router delegate:(id<FBiOSActionReaderDelegate>)delegate port:(in_port_t)port
{
  return [[FBiOSActionSocket alloc] initWithDelegate:delegate router:router port:port];
}

+ (instancetype)fileReaderForTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSActionReaderDelegate>)delegate readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle
{
  FBiOSActionRouter *router = [FBiOSActionRouter routerForTarget:target];
  return [self fileReaderForRouter:router delegate:delegate readHandle:readHandle writeHandle:writeHandle];
}

+ (instancetype)fileReaderForRouter:(FBiOSActionRouter *)router delegate:(id<FBiOSActionReaderDelegate>)delegate readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle
{
  return [[FBiOSActionFileHandle alloc] initWithDelegate:delegate router:router readHandle:readHandle writeHandle:writeHandle];
}

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _delegate = delegate;
  _router = router;
  _completedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startListening
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBFuture<NSNull *> *)stopListening
{
  // If delegate is nil, this is a no-op.
  [self.delegate readerDidFinishReading:self];
  self.delegate = nil;
  [self.completedFuture resolveWithResult:NSNull.null];
  return self.completedFuture;
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeActionReader;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.completedFuture onQueue:dispatch_get_main_queue() respondToCancellation:^{
    return [self stopListening];
  }];
}

@end

@implementation FBiOSActionSocket

#pragma mark Initializerss

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router port:(in_port_t)port
{
  self = [super initWithDelegate:delegate router:router];
  if (!self) {
    return nil;
  }

  _reader = [FBSocketConnectionManager socketReaderOnPort:port delegate:self];

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startListening
{
  if (!self.reader) {
    return [[FBControlCoreError
      describe:@"Cannot start listening when it's been stopped already"]
      failFuture];
  }
  return [self.reader startListening];
}

- (FBFuture<NSNull *> *)stopListening
{
  if (!self.reader) {
    return [[FBControlCoreError
      describe:@"Cannot stop listening, there is no active reader"]
      failFuture];
  }
  FBFuture<NSNull *> *future = [FBFuture futureWithFutures:@[[self.reader stopListening], [super stopListening]]];
  self.reader = nil;
  return future;
}

#pragma mark FBSocketConnectionManagerDelegate Implementation

- (id<FBSocketConsumer>)consumerWithClientAddress:(struct in6_addr)clientAddress
{
  return [[FBiOSActionReaderMediator alloc] initWithReader:self router:self.router delegate:self.delegate writeBack:FBFileWriter.nullWriter];
}

@end

@implementation FBiOSActionFileHandle

#pragma mark Initializerss

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle
{
  self = [super initWithDelegate:delegate router:router];
  if (!self) {
    return nil;
  }

  _reader = [FBFileReader readerWithFileDescriptor:readHandle.fileDescriptor closeOnEndOfFile:NO consumer:self logger:nil];
  _writer = [FBFileWriter syncWriterWithFileDescriptor:writeHandle.fileDescriptor closeOnEndOfFile:NO];
  _mediator = [[FBiOSActionReaderMediator alloc] initWithReader:self router:self.router delegate:self.delegate writeBack:self.writer];

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startListening
{
  if (!self.reader) {
    return [[FBControlCoreError
      describe:@"Cannot start listening when it's been stopped already"]
      failFuture];
  }
  return [self.reader startReading];
}

- (FBFuture<NSNull *> *)stopListening
{
  if (!self.reader || !self.writer) {
    return [[FBControlCoreError
      describe:@"Cannot stop listening when it's been stopped already"]
      failFuture];
  }
  FBFuture<NSNull *> *future = [FBFuture futureWithFutures:@[[self.reader stopReading], [super stopListening]]];
  self.reader = nil;
  self.writer = nil;
  return future;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [self.mediator consumeData:data];
}

- (void)consumeEndOfFile
{
  [self stopListening];
  [self.mediator consumeEndOfFile];
}

@end
