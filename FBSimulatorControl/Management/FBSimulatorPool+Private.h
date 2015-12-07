/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorPool.h>

@class FBProcessQuery;

@interface FBSimulatorPool ()

@property (nonatomic, strong, readonly) SimDeviceSet *deviceSet;
@property (nonatomic, strong, readonly) FBProcessQuery *processQuery;

@property (nonatomic, strong, readonly) NSMutableOrderedSet *allocatedUDIDs;
@property (nonatomic, strong, readonly) NSMutableDictionary *inflatedSimulators;

@end
