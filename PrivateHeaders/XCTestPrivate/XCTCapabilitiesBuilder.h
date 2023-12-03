/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTCapabilities;


@interface XCTCapabilitiesBuilder : NSObject
{
    NSMutableDictionary *_capabilitiesDictionary;
}

+ (id)capabilitiesFromProvider:(Class)arg1;

@property(readonly, copy) NSMutableDictionary *capabilitiesDictionary; // @synthesize capabilitiesDictionary=_capabilitiesDictionary;
@property(readonly, copy) XCTCapabilities *capabilities;
- (void)upgradeCapability:(id)arg1 toVersion:(unsigned long long)arg2;
- (void)registerCapability:(id)arg1;
- (void)registerCapability:(id)arg1 version:(unsigned long long)arg2;
- (id)init;

@end
