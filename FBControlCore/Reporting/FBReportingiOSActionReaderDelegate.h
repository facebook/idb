/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSActionReader.h>
#import <FBControlCore/FBEventInterpreter.h>
#import <FBControlCore/FBUploadBuffer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Takes in another FBiOSActionReaderDelegate and an FBEventInterpreter
 * Will return strings formatted by the given interpreter when possible
 * and pass through calls to the other delegate otherwise
 */
@interface FBReportingiOSActionReaderDelegate : NSObject <FBiOSActionReaderDelegate>

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate interpreter:(id<FBEventInterpreter>)interpreter;

@end

NS_ASSUME_NONNULL_END
