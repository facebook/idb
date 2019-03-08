/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDeviceIOInterface-Protocol.h>
#import <CoreSimulator/SimDeviceIOProtocol-Protocol.h>

@class NSString, SimDevice;

@interface SimDeviceIO : NSObject <SimDeviceIOInterface, SimDeviceIOProtocol>
{
    SimDevice *_device;
}

+ (id)ioForSimDevice:(id)arg1;
@property (nonatomic, weak) SimDevice *device;

- (void)detachConsumer:(id)arg1 fromPort:(id)arg2;
- (void)attachConsumer:(id)arg1 withUUID:(id)arg2 toPort:(id)arg3 errorQueue:(id)arg4 errorHandler:(id)arg5;
- (BOOL)unregisterService:(id)arg1 error:(id *)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(id)arg2 error:(id *)arg3;
- (id)ioPortForUUID:(id)arg1;
- (id)ioPorts;
- (id)initWithDevice:(id)arg1;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;
@property (atomic, readonly) NSUInteger hash;
@property (atomic, readonly) Class superclass;

@end
