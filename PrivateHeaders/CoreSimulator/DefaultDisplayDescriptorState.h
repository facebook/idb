/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDisplayDescriptorState-Protocol.h>

@interface DefaultDisplayDescriptorState : NSObject <SimDisplayDescriptorState>
{
    int _powerState;
    int _displayClass;
    unsigned int _defaultWidthForDisplay;
    unsigned int _defaultHeightForDisplay;
}

+ (id)defaultDisplayDescriptorStateWithPowerState:(int)arg1 displayClass:(int)arg2 width:(unsigned int)arg3 height:(unsigned int)arg4;
@property (nonatomic, assign) unsigned int defaultHeightForDisplay;
@property (nonatomic, assign) unsigned int defaultWidthForDisplay;
@property (nonatomic, assign) int displayClass;
@property (nonatomic, assign) int powerState;
- (id)xpcObject;

@end
