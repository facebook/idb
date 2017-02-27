/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
