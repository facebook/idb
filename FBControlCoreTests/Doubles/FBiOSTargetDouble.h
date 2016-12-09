/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@interface FBiOSTargetDouble : NSObject <FBiOSTarget>

@property (nonatomic, copy, readwrite) NSString *udid;

@property (nonatomic, copy, readwrite) NSString *name;

@property (nonatomic, copy, readwrite) NSString *auxillaryDirectory;

@property (nonatomic, strong, readwrite) FBiOSTargetDiagnostics *diagnostics;

@property (nonatomic, assign, readwrite) FBSimulatorState state;

@property (nonatomic, assign, readwrite) FBiOSTargetType targetType;

@property (nonatomic, copy, readwrite) FBProcessInfo *containerApplication;

@property (nonatomic, copy, readwrite) FBProcessInfo *launchdProcess;

@property (nonatomic, copy, readwrite) id<FBControlCoreConfiguration_Device> deviceConfiguration;

@property (nonatomic, copy, readwrite) id<FBControlCoreConfiguration_OS> osConfiguration;

@end
