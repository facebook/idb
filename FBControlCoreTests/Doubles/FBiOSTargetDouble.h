/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@interface FBiOSTargetDouble : NSObject <FBiOSTarget>

@property (nonatomic, strong, readonly) NSArray<Class> *actionClasses;

@property (nonatomic, copy, readwrite) NSString *uniqueIdentifier;

@property (nonatomic, copy, readwrite) NSString *udid;

@property (nonatomic, copy, readwrite) NSString *name;

@property (nonatomic, copy, readwrite) NSString *auxillaryDirectory;

@property (nonatomic, strong, readwrite) FBiOSTargetDiagnostics *diagnostics;

@property (nonatomic, assign, readwrite) FBiOSTargetState state;

@property (nonatomic, assign, readwrite) FBiOSTargetType targetType;

@property (nonatomic, copy, readwrite) FBProcessInfo *containerApplication;

@property (nonatomic, copy, readwrite) FBProcessInfo *launchdProcess;

@property (nonatomic, copy, readwrite) FBDeviceType *deviceType;

@property (nonatomic, copy, readwrite) FBOSVersion *osVersion;

@end
