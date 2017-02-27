/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/NSMutableData.h>

@interface NSMutableData (AVCCFormat)
+ (id)dataWithAVCCForConfigurationVersion:(id)arg1 avcProfileIndication:(id)arg2 profileCompatibility:(id)arg3 avcLevelIndication:(id)arg4 lengthSize:(id)arg5 sequenceParameterSets:(id)arg6 pictureParameterSets:(id)arg7;
@end
