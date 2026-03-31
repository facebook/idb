/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLogCommands.h"

#import "FBAMDServiceConnection.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"

#pragma mark Protocol Adaptor

@interface FBDeviceLogOperation : NSObject <FBLogOperation>

@property (nonatomic, readonly, strong) FBFileReader *reader;
@property (nonatomic, readonly, strong) FBFuture<NSNull *> *readCompleted;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *serviceCompleted;

@end

@implementation FBDeviceLogOperation

@synthesize consumer = _consumer;

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer readCompleted:(FBFuture<NSNull *> *)readCompleted serviceCompleted:(FBMutableFuture<NSNull *> *)serviceCompleted
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _readCompleted = readCompleted;
  _serviceCompleted = serviceCompleted;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return self.serviceCompleted;
}

@end

#pragma mark FBDeviceLogCommands Implementation

@interface FBDeviceLogCommands ()

@property (nonatomic, readonly, weak) FBDevice *device;

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

- (FBFuture<id<FBLogOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  if (arguments.count != 0) {
    NSString *unsupportedArgumentsMessage = [NSString stringWithFormat:@"[FBDeviceLogCommands][rdar://38452839] Unsupported arguments: %@", arguments];
    [consumer consumeData:[unsupportedArgumentsMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [self.device.logger log:unsupportedArgumentsMessage];
  }
  dispatch_queue_t queue = self.device.asyncQueue;
  dispatch_queue_t readQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.device_log_consumer", DISPATCH_QUEUE_SERIAL);
  return [[[self.device
            startService:@"com.apple.syslog_relay"]
           onQueue:queue
           pend:^(FBAMDServiceConnection *connection) {
             id<FBFileReaderProtocol> reader = [connection readFromConnectionWritingToConsumer:consumer onQueue:readQueue];
             return [[reader startReading] mapReplace:reader];
           }]
          onQueue:queue
          enter:^(id<FBFileReaderProtocol> reader, FBMutableFuture<NSNull *> *teardown) {
            FBFuture<NSNull *> *readCompleted = [[reader finishedReading] mapReplace:NSNull.null];
            return [[FBDeviceLogOperation alloc] initWithConsumer:consumer readCompleted:readCompleted serviceCompleted:teardown];
          }];
}

@end
