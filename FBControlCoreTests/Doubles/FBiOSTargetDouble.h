/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@interface FBiOSTargetDouble : NSObject <FBiOSTarget>

@property (nonatomic, readwrite, copy) NSString *uniqueIdentifier;

@property (nonatomic, readwrite, copy) NSString *udid;

@property (nonatomic, readwrite, copy) NSString *name;

@property (nonatomic, readwrite, copy) NSString *auxillaryDirectory;

@property (nonatomic, readwrite, copy) NSString *customDeviceSetPath;

@property (nonatomic, readwrite, strong) FBiOSTargetDiagnostics *diagnostics;

@property (nonatomic, readwrite, assign) FBiOSTargetState state;

@property (nonatomic, readwrite, assign) FBiOSTargetType targetType;

@property (nonatomic, readwrite, copy) FBDeviceType *deviceType;

@property (nonatomic, readwrite, copy) FBOSVersion *osVersion;

@end
