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
 An FBiOSActionReaderDelegate that reports events.
 */
@interface FBReportingiOSActionReaderDelegate : NSObject <FBiOSActionReaderDelegate>

/**
 The Designated Initializer.

 @param reporter the underlying event interpreter.
 @return a new Delegate Instance.
 */
- (instancetype)initWithReporter:(id<FBEventReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
