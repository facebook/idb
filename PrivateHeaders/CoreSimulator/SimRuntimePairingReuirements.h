/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
