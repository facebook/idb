/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSString;

@interface DVTArchitecture : NSObject
{
    BOOL _is64Bit;
    int _CPUType;
    int _CPUSubType;
    NSString *_canonicalName;
    NSString *_displayName;
}

+ (id)architectureWithCPUType:(int)arg1 subType:(int)arg2;
+ (id)architectureWithCanonicalName:(id)arg1;
+ (id)allArchitectures;
+ (void)initialize;
@property(readonly) BOOL is64Bit; // @synthesize is64Bit=_is64Bit;
@property(readonly) int CPUSubType; // @synthesize CPUSubType=_CPUSubType;
@property(readonly) int CPUType; // @synthesize CPUType=_CPUType;
@property(readonly, copy) NSString *displayName; // @synthesize displayName=_displayName;
@property(readonly, copy) NSString *canonicalName; // @synthesize canonicalName=_canonicalName;

- (_Bool)matchesCPUType:(int)arg1 andSubType:(int)arg2;
- (id)description;
- (id)initWithExtension:(id)arg1;
- (id)initWithCanonicalName:(id)arg1 displayName:(id)arg2 CPUType:(int)arg3 CPUSubType:(int)arg4 is64Bit:(BOOL)arg5;

@end

