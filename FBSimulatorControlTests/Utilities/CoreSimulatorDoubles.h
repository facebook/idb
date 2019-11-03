/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>

@interface FBSimulatorControlTests_SimDeviceType_Double : NSObject

@property (nonatomic, readwrite, copy) NSString *name;

@end

@interface FBSimulatorControlTests_SimDeviceRuntime_Double : NSObject

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *versionString;

@end

@interface FBSimulatorControlTests_SimDevice_Double : NSObject

@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSUUID *UDID;
@property (nonatomic, readwrite, copy) NSString *dataPath;
@property (nonatomic, readwrite, assign) unsigned long long state;
@property (nonatomic, readwrite, strong) FBSimulatorControlTests_SimDeviceType_Double *deviceType;
@property (nonatomic, readwrite, strong) FBSimulatorControlTests_SimDeviceRuntime_Double *runtime;
@property (nonatomic, readwrite, strong) SimDeviceNotificationManager *notificationManager;

@end

@interface FBSimulatorControlTests_SimDeviceSet_Double : NSObject

@property (nonatomic, readwrite, copy) NSArray *availableDevices;
@property (nonatomic, readwrite, strong) SimDeviceNotificationManager *notificationManager;

@end
