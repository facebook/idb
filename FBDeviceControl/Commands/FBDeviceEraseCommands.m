/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceEraseCommands.h"

#import <FBDeviceControl/FBDeviceControl-Swift.h>

#import "FBAMDevice.h"
#import "FBAMRestorableDeviceManager.h"
#import "FBDevice.h"

@interface FBDeviceEraseOperation : NSObject <FBiOSTargetSetDelegate>

@property (nonatomic, readonly, copy) NSString *udid;
@property (nonatomic, readonly, copy) NSString *ecid;
@property (nonatomic, readonly, assign) AMDCalls calls;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nonatomic, readonly, strong) FBAMRestorableDeviceManager *deviceManager;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNumber *> *eraseCallbackResult;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *deviceDetected;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *deviceWentAway;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *deviceCameBack;
@property (nonatomic, readonly, strong) dispatch_queue_t queue;

@end

static int const EraseCallbackValueGood = -10;
static NSTimeInterval const DetectTimeout = 10;
static NSTimeInterval const APICallbackTimeout = 15;
static NSTimeInterval const OfflineTimeout = 20;
static NSTimeInterval const OnlineTimeout = 300;

static int EraseCallback(NSString *identifier, int progress, void *context)
{
  FBDeviceEraseOperation *operation = (__bridge FBDeviceEraseOperation *)(context);
  [operation.logger log:[NSString stringWithFormat:@"Erase Callback is %d", progress]];
  [operation.eraseCallbackResult resolveWithResult:@(progress)];
  return 0;
}

@implementation FBDeviceEraseOperation

+ (instancetype)operationWithDevice:(FBDevice *)device logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdeviceerase", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithUDID:device.udid ecid:device.uniqueIdentifier calls:device.calls queue:queue logger:logger];
}

- (instancetype)initWithUDID:(NSString *)udid ecid:(NSString *)ecid calls:(AMDCalls)calls queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = udid;
  _ecid = ecid;
  _logger = logger;
  _calls = calls;
  _queue = queue;
  _deviceManager = [[FBAMRestorableDeviceManager alloc] initWithCalls:calls workQueue:queue asyncQueue:queue ecidFilter:ecid logger:logger];
  _deviceManager.delegate = self;
  _eraseCallbackResult = FBMutableFuture.future;
  _deviceDetected = FBMutableFuture.future;
  _deviceWentAway = FBMutableFuture.future;
  _deviceCameBack = FBMutableFuture.future;

  return self;
}

#pragma mark Erase

- (FBFuture<NSNull *> *)erase
{
  FBAMRestorableDeviceManager *deviceManager = self.deviceManager;
  FBFuture<NSNull *> *deviceCameBack = self.deviceCameBack;
  FBFuture<NSNull *> *deviceWentAway = self.deviceWentAway;
  id<FBControlCoreLogger> logger = self.logger;
  return [[[[FBFuture
             onQueue:self.queue
             resolve:^FBFuture<NSNull *> * {
               NSError *error = nil;
               if (![deviceManager startListeningWithError:&error]) {
                 return [FBFuture futureWithError:error];
               }
               return [[self deviceDetected] timeout:DetectTimeout waitingFor:@"Device to be detected the first time"];
             }]
            onQueue:self.queue
            fmap:^FBFuture<NSNull *> *(id _) {
              [logger log:@"Device has been detected, starting erase API Call"];
              return [[self startErase] timeout:APICallbackTimeout waitingFor:@"Device erase API call to resolve"];
            }]
           onQueue:self.queue
           fmap:^FBFuture<NSNull *> *(NSNumber *eraseCallbackValueNumber) {
             const int eraseCallbackValue = eraseCallbackValueNumber.intValue;
             if (eraseCallbackValue != EraseCallbackValueGood) {
               return (FBFuture *)[[FBDeviceControlError
                                    describe:[NSString stringWithFormat:@"Erase callback was %d, not %d. Perhaps the device is not activated?", eraseCallbackValue, EraseCallbackValueGood]]
                                   failFuture];
             }
             [logger log:@"Device API call finished, waiting for device to go offline"];
             return [deviceWentAway timeout:OfflineTimeout waitingFor:@"Device to go offline"];
           }]
          onQueue:self.queue
          fmap:^FBFuture<NSNull *> *(id _) {
            [logger log:@"Device has gone offline, waiting for it to come back online"];
            return [deviceCameBack timeout:OnlineTimeout waitingFor:@"Device to come back"];
          }];
}

- (FBFuture<NSNumber *> *)startErase
{
  AMDCalls calls = self.calls;
  FBFuture<NSNumber *> *eraseCallbackResult = self.eraseCallbackResult;
  id<FBControlCoreLogger> logger = self.logger;
  NSString *udid = self.udid;
  return [FBFuture
          onQueue:self.queue
          resolve:^FBFuture<NSNumber *> * {
            calls.AMSInitialize(0);
            int status = calls.AMSEraseDevice((__bridge CFStringRef)(udid), EraseCallback, (__bridge void *)(self));
            [logger log:[NSString stringWithFormat:@"AMSEraseDevice had status %d", status]];
            return eraseCallbackResult;
          }];
}

#pragma mark FBiOSTargetSetDelegate

- (void)targetAdded:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  if (self.deviceDetected.state == FBFutureStateRunning) {
    [self.logger log:[NSString stringWithFormat:@"Got target %@ added for the first time", targetInfo]];
    [self.deviceDetected resolveWithResult:NSNull.null];
  } else {
    [self.logger log:[NSString stringWithFormat:@"Got target %@ added", targetInfo]];
    [self.deviceCameBack resolveWithResult:NSNull.null];
  }
}

- (void)targetRemoved:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  [self.logger log:[NSString stringWithFormat:@"Got target %@ removed", targetInfo]];
  [self.deviceWentAway resolveWithResult:NSNull.null];
}

- (void)targetUpdated:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{}

@end

@interface FBDeviceEraseCommands ()

@property (nonatomic, readonly, weak) FBDevice *device;
@property (nonatomic, readwrite, strong) FBAMRestorableDeviceManager *restorableDeviceManager;

@end

@implementation FBDeviceEraseCommands

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

#pragma mark FBEraseCommands Implementation

- (FBFuture<NSNull *> *)erase
{
  id<FBControlCoreLogger> logger = [self.device.logger withName:[NSString stringWithFormat:@"erase_%@", self.device.udid]];
  return [[self.device
           activate]
          onQueue:self.device.workQueue
          fmap:^(id _) {
            FBDeviceEraseOperation *operation = [FBDeviceEraseOperation operationWithDevice:self.device logger:logger];
            return [[operation
                     erase]
                    onQueue:self.device.workQueue
                    doOnResolved:^(id __) {
                      [logger log:[NSString stringWithFormat:@"Device erase finished successfully %@", operation]];
                    }];
          }];
}

@end
