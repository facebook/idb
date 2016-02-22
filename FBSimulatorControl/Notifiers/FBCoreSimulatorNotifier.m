/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

+ (instancetype)notifierForSimulator:(FBSimulator *)simulator block:(void (^)(NSDictionary *info))block
{
  return [self notifierForSimDevice:simulator.device block:block];
}

+ (instancetype)notifierForSimDevice:(SimDevice *)simDevice block:(void (^)(NSDictionary *info))block
{
  id<SimDeviceNotifier> notifier = simDevice.notificationManager;
  return [[self alloc] initWithNotifier:notifier block:block];
}

+ (instancetype)notifierForSet:(FBSimulatorSet *)set block:(void (^)(NSDictionary *info))block;
{
  id<SimDeviceNotifier> notifier = set.deviceSet.notificationManager;
  return [[self alloc] initWithNotifier:notifier block:block];
}

- (instancetype)initWithNotifier:(id<SimDeviceNotifier>)notifier block:(void (^)(NSDictionary *info))block
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _notifier = notifier;
  _handle = [notifier registerNotificationHandler:^(NSDictionary *info) {
    dispatch_async(dispatch_get_main_queue(), ^{
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
