/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBIPCClient;
@class FBIPCServer;
@class FBSimulatorSet;

/**
 Manages the IPC Client and Server.
 */
@interface FBIPCManager : NSObject

/**
 Creates an IPC Manager for the Provided Simulator Set.
 */
+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set;

/**
 The Client that messages can be sent to.
 */
@property (nonatomic, strong, readonly) FBIPCClient *client;

/**
 The Server that will recieve messages.
 */
@property (nonatomic, strong, readonly) FBIPCServer *server;

@end
