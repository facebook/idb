/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class DVTLocalComputer, NSMapTable, NSMutableDictionary, NSMutableSet, NSSet;

@interface DVTDeviceManager : NSObject
{
    NSMutableDictionary *_locatorTrackers;
    NSMapTable *_observingTokens;
    NSMutableSet *_availableDevices;
    DVTLocalComputer *_localComputer;
}

+ (id)defaultDeviceManager;
+ (void)initialize;

- (id)deviceLocatorForDeviceType:(id)arg1;
- (id)searchForDevicesWithType:(id)arg1 options:(id)arg2 timeout:(double)arg3 error:(id *)arg4;
- (id)searchForDeviceWithType:(id)arg1 options:(id)arg2 genericOnly:(BOOL)arg3 timeout:(double)arg4 error:(id *)arg5;
- (id)_searchForDevicesWithType:(id)arg1 options:(id)arg2 genericOnly:(BOOL)arg3 allowMultiple:(BOOL)arg4 timeout:(double)arg5 error:(id *)arg6;
- (id)_waitForDeviceUsingLocatorsToOptions:(id)arg1 genericOnly:(BOOL)arg2 allowMultiple:(BOOL)arg3 timeout:(double)arg4 error:(id *)arg5;
- (id)_lookUpAvailableDevicesUsingLocatorsToOptions:(id)arg1 genericOnly:(BOOL)arg2 allowMultiple:(BOOL)arg3 error:(id *)arg4;
- (id)_deviceLocatorForDeviceSpecifierPrefix:(id)arg1 error:(id *)arg2;
- (BOOL)locateOnlyLocalComputerWithError:(id *)arg1;
- (void)locateOnlyLocalComputer;
- (void)stopLocating;
- (BOOL)startLocatingWithError:(NSError **)arg1;
- (void)startLocating;
- (void)_adjustAvailableDevicesForChangeKind:(unsigned long long)arg1 addedObjects:(id)arg2 removedObjects:(id)arg3;
- (void)_stopObservingDevice:(id)arg1;
- (void)_startObservingDevice:(id)arg1;
- (id)_discoverDeviceLocators;
- (id)deviceAtDeviceLocation:(id)arg1;
- (id)_deviceLocatorForDeviceLocationScheme:(id)arg1;
- (id)devicesMatchingPredicate:(id)arg1;
@property(readonly) DVTLocalComputer *localComputer;
- (id)init;

// Remaining properties
@property(copy) NSSet *availableDevices; // @dynamic availableDevices;
@property(readonly, copy) NSMutableSet *mutableAvailableDevices; // @dynamic mutableAvailableDevices;

@end

