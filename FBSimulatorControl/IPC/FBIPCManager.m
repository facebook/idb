/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBIPCManager.h"

#import "FBIPCClient.h"
#import "FBIPCServer.h"

NSString *const FBVideoStartDistributedNotificationName = @"FBSIMULATORCONTROL_VIDEO_START";
NSString *const FBVideoStopDistributedNotificationName = @"FBSIMULATORCONTROL_VIDEO_STOP";
NSString *const FBDistributedNotificationUDIDKey = @"udid";

@implementation FBIPCManager

+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set
{
  FBIPCClient *client = [FBIPCClient withSimulatorSet:set];
  FBIPCServer *server = [FBIPCServer withSimulatorSet:set];
  return [[self alloc] initWithClient:client server:server];
}

- (instancetype)initWithClient:(FBIPCClient *)client server:(FBIPCServer *)server
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _client = client;
  _server = server;

  return self;
}

@end
