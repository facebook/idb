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

@protocol FBFileConsumer;

/**
 An FBiOSActionReaderDelegate for interpreting events.
 Returns strings formatted by the given interpreter when possible
 and pass through calls to the other delegate otherwise
 */
@interface FBReportingiOSActionReaderDelegate : NSObject <FBiOSActionReaderDelegate>

/**
 The Designated Initializer.

 @param delegate the delegate to forward to.
 @param reporter the underlying event interpreter.
 @return a new Delegate Instance.
 */
- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate reporter:(id<FBEventReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
