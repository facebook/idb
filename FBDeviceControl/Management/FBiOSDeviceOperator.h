/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTestBootstrap/FBDeviceOperator.h>
#import "FBCodesignProvider.h"

/**
 Operator that uses DVTFoundation and IDEiOSSupportCore.ideplugin to control DVTiOSDevice directly
 */
@interface FBiOSDeviceOperator : NSObject <FBDeviceOperator>

/**
 Convenience constructor

 @param deviceUDID UDID used to find device
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return operator if device is found, otherwise nil
 */
+ (instancetype)operatorWithDeviceUDID:(NSString *)deviceUDID
                      codesignProvider:(id<FBCodesignProvider>)codesignProvider
                                 error:(NSError **)error;

@end
