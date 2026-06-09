/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMachPort, NSString;
@protocol OS_dispatch_queue, OS_dispatch_source;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): the mach-port server helper. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimMachPortServer : NSObject
{
  NSMachPort *_port;
  NSString *_name;
  NSObject<OS_dispatch_queue> *_serverQueue;
  NSObject<OS_dispatch_source> *_serverSource;
}

@property (nonatomic, retain) NSObject<OS_dispatch_source> *serverSource;
@property (nonatomic, retain) NSObject<OS_dispatch_queue> *serverQueue;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, retain) NSMachPort *port;

- (id)description;
- (id)initWithName:(id)arg1 machMessageHandler:(CDUnknownFunctionPointerType)arg2 machMessageSize:(unsigned int)arg3;

@end
