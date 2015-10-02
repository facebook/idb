/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

@interface FBSimulatorControlTests_SimDevice_Double : NSObject

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSUUID *UDID;
@property (nonatomic, readwrite, assign) unsigned long long state;

@end

@interface FBSimulatorControlTests_SimDeviceSet_Double : NSObject

@property (nonatomic, readwrite, copy) NSArray *availableDevices;

@end
