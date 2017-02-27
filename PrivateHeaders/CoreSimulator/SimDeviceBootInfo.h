/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <objc/NSObject.h>

#import <CoreSimulator/NSSecureCoding-Protocol.h>

@class NSDictionary, NSString;

@interface SimDeviceBootInfo : NSObject <NSSecureCoding>
{
    BOOL _isTerminalStatus;
    unsigned int _status;
    double _bootElapsedTime;
    NSDictionary *_info;
}

+ (BOOL)supportsSecureCoding;
@property (nonatomic, copy) NSDictionary *info;
@property (nonatomic, assign) BOOL isTerminalStatus;
@property (nonatomic, assign) double bootElapsedTime;
@property (nonatomic, assign) unsigned int status;
- (void).cxx_destruct;
@property (readonly, nonatomic) double migrationElapsedTime;
@property (nonatomic, copy, readonly) NSString *migrationPhaseDescription;
- (void)encodeWithCoder:(id)arg1;
- (unsigned long long)hash;
- (BOOL)isEqual:(id)arg1;
- (id)initWithCoder:(id)arg1;
- (id)initWithElapsedTime:(double)arg1 status:(unsigned int)arg2 info:(id)arg3;

@end
