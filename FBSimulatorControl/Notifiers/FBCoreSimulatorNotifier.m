/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCoreSimulatorNotifier.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceNotificationManager.h>
#import <CoreSimulator/SimDeviceNotifier-Protocol.h>
#import <CoreSimulator/SimDeviceSet.h>

#import "FBSimulator.h"
#import "FBSimulatorSet.h"

@interface FBCoreSimulatorNotifier ()

@property (nonatomic, readonly, assign) unsigned long long handle;
@property (nonatomic, readonly, strong) id notifier;

@end

@implementation FBCoreSimulatorNotifier

+ (instancetype)notifierForSimDevice:(SimDevice *)simDevice queue:(dispatch_queue_t)queue block:(void (^)(NSDictionary *info))block
{
  id<SimDeviceNotifier> notifier = simDevice.notificationManager;
  return [[self alloc] initWithNotifier:notifier queue:queue block:block];
}

+ (instancetype)notifierForSet:(FBSimulatorSet *)set queue:(dispatch_queue_t)queue block:(void (^)(NSDictionary *info))block
{
  id<SimDeviceNotifier> notifier = set.deviceSet.notificationManager;
  return [[self alloc] initWithNotifier:notifier queue:queue block:block];
}

- (instancetype)initWithNotifier:(id<SimDeviceNotifier>)notifier queue:(dispatch_queue_t)queue block:(void (^)(NSDictionary *info))block
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _notifier = notifier;
  _handle = [notifier registerNotificationHandler:^(NSDictionary *info) {
    dispatch_async(queue, ^{
      block(info);
    });
  }];

  return self;
}

- (void)terminate
{
  [self.notifier unregisterNotificationHandler:self.handle error:nil];
}

@end
