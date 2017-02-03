/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreSimulator/SimDeviceIO.h>

#import <CoreSimulator/SimDeviceIOInterface-Protocol.h>

@class NSArray, NSDictionary;

@interface SimDeviceIOServer : SimDeviceIO <SimDeviceIOInterface>
{
    NSDictionary *_loadedBundles;
    NSArray *_ioPorts;
    NSArray *_ioPortProxies;
}

@property (nonatomic, copy) NSArray *ioPortProxies;
@property (nonatomic, copy) NSArray *ioPorts;
@property (nonatomic, copy) NSDictionary *loadedBundles;

- (BOOL)unregisterService:(id)arg1 error:(id *)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(id)arg2 error:(id *)arg3;
- (id)tvOutDisplayDescriptorState;
- (id)mainDisplayDescriptorState;
- (id)integratedDisplayDescriptorState;
- (BOOL)unloadAllBundles;
- (BOOL)loadAllBundles;

@end
