/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class NSArray;

@interface SimRuntimePairingReuirements : NSObject
{
    unsigned int _minOSVersion;
    NSArray *_supportedProductFamilies;
    unsigned long long _maxPairs;
}

@property (nonatomic, assign) unsigned long long maxPairs;
@property (copy, nonatomic) NSArray *supportedProductFamilies;
@property (nonatomic, assign) unsigned int minOSVersion;


@end
