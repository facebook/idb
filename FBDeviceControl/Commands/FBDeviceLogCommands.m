/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLogCommands.h"

#import "FBDevice+Private.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

#pragma mark Protocol Adaptor

@interface FBDeviceLogOperation : NSObject <FBLogOperation>

@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completed;

@end

@implementation FBDeviceLogOperation

@synthesize completed = _completed;
@synthesize consumer = _consumer;

- (instancetype)initWithReader:(FBFileReader *)reader consumer:(id<FBDataConsumer>)consumer completed:(FBMutableFuture<NSNull *> *)completed
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _reader = reader;
  _consumer = consumer;
  _completed = completed;

  return self;
}

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeLogTail;
}

@end

#pragma mark FBDeviceLogCommands Implementation

@interface FBDeviceLogCommands()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBLogCommands Implementation

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  return [[FBDeviceControlError describeFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] failFuture];
}

- (FBFuture<id<FBLogOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  if (arguments.count != 0) {
    NSString *unsupportedArgumentsMessage = [NSString stringWithFormat:@"[FBDeviceLogCommands][rdar://38452839] Unsupported arguments: %@", arguments];
    [consumer consumeData:[unsupportedArgumentsMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [self.device.logger log:unsupportedArgumentsMessage];
  }
  id<FBControlCoreLogger> logger = self.device.logger;

  dispatch_queue_t queue = self.device.asyncQueue;
  return [[[self.device.amDevice
    startService:@"com.apple.syslog_relay"]
    onQueue:queue push:^(FBAMDServiceConnection *connection) {
      [logger logFormat:@"Reading log data from %@", connection];
      FBFileReader *reader = [FBFileReader readerWithFileDescriptor:connection.socket closeOnEndOfFile:NO consumer:consumer logger:nil];
      return [[[reader
        startReading]
        onQueue:queue contextualTeardown:^(id _, FBFutureState __) {
           return [reader stopReading];
        }]
        onQueue:queue pend:^(id _) {
          return [FBFuture futureWithResult:reader];
        }];
    }]
    onQueue:queue enter:^(FBFileReader *reader, FBMutableFuture<NSNull *> *teardown) {
      return [[FBDeviceLogOperation alloc] initWithReader:reader consumer:consumer completed:teardown];
    }];
}

@end
