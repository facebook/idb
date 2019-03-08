/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMachPort, NSString;
@protocol OS_dispatch_queue, OS_dispatch_source;

@interface SimMachPortServer : NSObject
{
    NSMachPort *_port;
    NSString *_name;
    NSObject<OS_dispatch_queue> *_serverQueue;
    NSObject<OS_dispatch_source> *_serverSource;
}

@property (retain, nonatomic) NSObject<OS_dispatch_source> *serverSource;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *serverQueue;
@property (nonatomic, copy) NSString *name;
@property (retain, nonatomic) NSMachPort *port;

- (id)description;
- (id)initWithName:(id)arg1 machMessageHandler:(CDUnknownFunctionPointerType)arg2 machMessageSize:(unsigned int)arg3;

@end
