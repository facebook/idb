/**
 * Copyright (c) 2017-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceLogCommands.h"

#import "FBDevice+Private.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

#pragma mark Protocol Adaptor

@interface FBDeviceLogTerminationContinuation : NSObject <FBiOSTargetContinuation>

- (instancetype)initWithReader:(FBFileReader *)reader completed:(FBMutableFuture<NSNull *> *)completed;

@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completed;

@end

@implementation FBDeviceLogTerminationContinuation

@synthesize completed = _completed;

- (instancetype)initWithReader:(FBFileReader *)reader completed:(FBMutableFuture<NSNull *> *)completed
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _reader = reader;
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

- (FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  if (arguments.count == 0) {
    NSString *unsupportedArgumentsMessage = [NSString stringWithFormat:@"[FBDeviceLogCommands][rdar://38452839] Unsupported arguments: %@", arguments];
    [consumer consumeData:[unsupportedArgumentsMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [self.device.logger log:unsupportedArgumentsMessage];
  }

  dispatch_queue_t queue = self.device.asyncQueue;
  return [[[self.device.amDevice
    startService:@"com.apple.syslog_relay"]
    onQueue:queue pend:^(FBAMDServiceConnection *connection) {
      NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:connection.socket closeOnDealloc:YES];
      FBFileReader *reader = [FBFileReader readerWithFileHandle:handle consumer:consumer logger:nil];
      return [[reader startReading] mapReplace:reader];
    }]
    onQueue:queue enter:^(FBFileReader *reader, FBMutableFuture<NSNull *> *teardown) {
      return [[FBDeviceLogTerminationContinuation alloc] initWithReader:reader completed:teardown];
    }];
}

@end
