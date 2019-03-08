/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/NSObject.h>

#import <CoreSimulator/SimDisplayDescriptorState-Protocol.h>

@class NSString;

@interface SimDisplayDefaultDescriptorState : NSObject <SimDisplayDescriptorState>
{
    unsigned short _displayClass;
    int _powerState;
    unsigned int _defaultWidthForDisplay;
    unsigned int _defaultHeightForDisplay;
    unsigned int _defaultPixelFormat;
}

+ (id)defaultDisplayDescriptorStateWithPowerState:(int)arg1 displayClass:(unsigned short)arg2 width:(unsigned int)arg3 height:(unsigned int)arg4 pixelFormat:(unsigned int)arg5;
@property (nonatomic, assign) unsigned int defaultPixelFormat;
@property (nonatomic, assign) unsigned int defaultHeightForDisplay;
@property (nonatomic, assign) unsigned int defaultWidthForDisplay;
@property (nonatomic, assign) unsigned short displayClass;
@property (nonatomic, assign) int powerState;
- (id)xpcObject;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;
@property (atomic, readonly) unsigned long long hash;
@property (atomic, readonly) Class superclass;

@end
