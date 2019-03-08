/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
