/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLogCommands.h"

#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

#pragma mark Protocol Adaptor

@interface FBDeviceLogOperation : NSObject <FBLogOperation>

@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *readCompleted;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *serviceCompleted;

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

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeLogTail;
}

- (FBFuture<NSNull *> *)completed
{
  return self.serviceCompleted;
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
  dispatch_queue_t queue = self.device.asyncQueue;
  return [[self.device
    startService:@"com.apple.syslog_relay"]
    onQueue:queue enter:^(FBAMDServiceConnection *connection, FBMutableFuture<NSNull *> *teardown) {
      FBFuture<NSNull *> *readCompleted = [connection consume:consumer onQueue:dispatch_queue_create("com.facebook.fbdevicecontrol.device_log_consumer", DISPATCH_QUEUE_SERIAL)];
      return [[FBDeviceLogOperation alloc] initWithConsumer:consumer readCompleted:readCompleted serviceCompleted:teardown];
    }];
}

@end
