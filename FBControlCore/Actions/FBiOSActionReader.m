/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSActionReader.h"

#import "FBUploadBuffer.h"
#import "FBFileReader.h"
#import "FBFileWriter.h"
#import "FBiOSActionRouter.h"
#import "FBiOSTarget.h"
#import "FBiOSTargetAction.h"
#import "FBLineBuffer.h"
#import "FBSocketReader.h"

FBTerminationHandleType const FBTerminationHandleTypeActionReader = @"action_reader";

@interface FBiOSActionReader ()

@property (nonatomic, strong, nullable, readwrite) id<FBiOSActionReaderDelegate> delegate;
@property (nonatomic, strong, readonly) FBiOSActionRouter *router;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router;

@end

@interface FBiOSActionReaderMediator : NSObject <FBSocketConsumer, FBiOSTargetActionDelegate>

@property (nonatomic, strong, readonly) FBiOSActionReader *reader;
@property (nonatomic, strong, readonly) FBLineBuffer *lineBuffer;
@property (nonatomic, strong, readwrite, nullable) FBUploadBuffer *uploadBuffer;

@end

@implementation FBiOSActionReaderMediator

- (instancetype)initWithReader:(FBiOSActionReader *)reader
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reader = reader;
  _lineBuffer = [FBLineBuffer new];
  _uploadBuffer = nil;

  return self;
}

#pragma mark FBSocketConsumer Implementation

- (void)consumeData:(NSData *)data writeBack:(id<FBFileConsumer>)writeBack
{
  if (self.uploadBuffer) {
    NSData *remainder = nil;
    FBUploadedDestination *destination = [self.uploadBuffer writeData:data remainderOut:&remainder];
    if (destination) {
      [self dispatchUploadCompleted:destination writeBack:writeBack];
    }
    data = remainder;
  }
  if (!data) {
    return;
  }
  [self.lineBuffer appendData:data];
  [self runBufferWithWriteBack:writeBack];
}

#pragma mark FBiOSTargetActionDelegate Implementation

- (void)action:(id<FBiOSTargetAction>)action target:(id<FBiOSTarget>)target didGenerateTerminationHandle:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Private

- (void)runBufferWithWriteBack:(id<FBFileConsumer>)writeBack
{
  NSData *lineData = self.lineBuffer.consumeLineData;
  while (lineData) {
    [self dispatchLine:lineData writeBack:writeBack];
    lineData = self.lineBuffer.consumeLineData;
  }
}

- (void)dispatchLine:(NSData *)line writeBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);

  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:line options:0 error:&error];
  if (!json) {
    [self dispatchParseError:line error:error writeBack:writeBack];
    return;
  }

  id<FBiOSTargetAction> action = [self.reader.router actionFromJSON:json error:&error];
  if (!action) {
    [self dispatchParseError:line error:error writeBack:writeBack];
    return;
  }
  if ([action isKindOfClass:FBUploadHeader.class]) {
    [self dispatchUploadStarted:(FBUploadHeader *)action writeBack:writeBack];
    return;
  }
  [self dispatchAction:action writeBack:writeBack];
}

- (void)dispatchAction:(id<FBiOSTargetAction>)action writeBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);

  FBiOSActionReader *reader = self.reader;
  id<FBiOSTarget> target = reader.router.target;

  // Notify Delegate of the start of the Action.
  __block NSString *response = nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    response = [reader.delegate reader:reader willStartPerformingAction:action onTarget:target];
  });
  [self reportString:response toWriteBack:writeBack];

  // Run the action, on the main queue
  __block NSError *error = nil;
  __block BOOL success = NO;
  dispatch_sync(dispatch_get_main_queue(), ^{
    success = [action runWithTarget:target delegate:self error:&error];
  });

  // Notify the delegate that the reader has finished, report the resultant string.
  response = success
    ? [reader.delegate reader:reader didProcessAction:action onTarget:target]
    : [reader.delegate reader:reader didFailToProcessAction:action onTarget:target error:error];
  [self reportString:response toWriteBack:writeBack];
}

- (void)dispatchUploadStarted:(FBUploadHeader *)header writeBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);
  NSParameterAssert(self.uploadBuffer == nil);

  self.uploadBuffer = [FBUploadBuffer bufferWithHeader:header workingDirectory:self.reader.router.target.auxillaryDirectory];
  __block NSString *response = nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    response = [self.reader.delegate reader:self.reader willStartReadingUpload:header];
  });
  [self reportString:response toWriteBack:writeBack];

  // Push the buffer back through.
  NSData *remainder = [self.lineBuffer consumeCurrentData];
  [self consumeData:remainder writeBack:writeBack];
}

- (void)dispatchUploadCompleted:(FBUploadedDestination *)destination writeBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);
  NSParameterAssert(self.uploadBuffer != nil);

  self.uploadBuffer = nil;
  __block NSString *response = nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    [self.reader.delegate reader:self.reader didFinishUpload:destination];
  });
  [self reportString:response toWriteBack:writeBack];
}

- (void)dispatchParseError:(NSData *)lineData error:(NSError *)error writeBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);

  NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
  __block NSString *response = nil;
  dispatch_sync(dispatch_get_main_queue(), ^{
    response = [self.reader.delegate reader:self.reader failedToInterpretInput:line error:error];
  });
  if (!response) {
    return;
  }
  [self reportString:response toWriteBack:writeBack];
}

- (void)reportString:(nullable NSString *)string toWriteBack:(id<FBFileConsumer>)writeBack
{
  NSParameterAssert(NSThread.isMainThread == NO);

  if (!string) {
    return;
  }
  NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
  [writeBack consumeData:data];
}

@end

@interface FBiOSActionSocket : FBiOSActionReader <FBSocketReaderDelegate>

@property (nonatomic, strong, nullable, readwrite) FBSocketReader *reader;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router port:(in_port_t)port;

@end

@interface FBiOSActionFileHandle : FBiOSActionReader <FBFileConsumer>

@property (nonatomic, strong, readonly) FBiOSActionReaderMediator *mediator;
@property (nonatomic, strong, nullable, readwrite) FBFileReader *reader;
@property (nonatomic, strong, nullable, readwrite) FBFileWriter *writer;

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate router:(FBiOSActionRouter *)router readHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle;

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

  return self;
}

#pragma mark Public Methods

- (BOOL)startListeningWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  // If delegate is nil, this is a no-op.
  [self.delegate readerDidFinishReading:self];
  self.delegate = nil;
  return YES;
}

#pragma mark FBTerminationAwaitable

- (FBTerminationHandleType)type
{
  return FBTerminationHandleTypeActionReader;
}

- (void)terminate
{
  [self stopListeningWithError:nil];
}

- (BOOL)hasTerminated
{
  return self.delegate == nil;
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

  _reader = [FBSocketReader socketReaderOnPort:port delegate:self];

  return self;
}

#pragma mark Public Methods

- (BOOL)startListeningWithError:(NSError **)error
{
  return [self.reader startListeningWithError:error];
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  BOOL result = [self.reader stopListeningWithError:error] && [super stopListeningWithError:error];
  self.reader = nil;
  return result;
}

#pragma mark FBSocketReaderDelegate Implementation

- (id<FBSocketConsumer>)consumerWithClientAddress:(struct in6_addr)clientAddress
{
  return [[FBiOSActionReaderMediator alloc] initWithReader:self];
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

  _reader = [FBFileReader readerWithFileHandle:readHandle consumer:self];
  _writer = [FBFileWriter writerWithFileHandle:writeHandle blocking:YES];
  _mediator = [[FBiOSActionReaderMediator alloc] initWithReader:self];

  return self;
}

#pragma mark Public Methods

- (BOOL)startListeningWithError:(NSError **)error
{
  return [self.reader startReadingWithError:error];
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  BOOL result = [self.reader stopReadingWithError:error] && [super stopListeningWithError:error];
  self.reader = nil;
  self.writer = nil;
  return result;
}

#pragma mark FBFileConsumer

- (void)consumeData:(NSData *)data
{
  [self.mediator consumeData:data writeBack:self.writer];
}

- (void)consumeEndOfFile
{
  [self stopListeningWithError:nil];
}

@end
