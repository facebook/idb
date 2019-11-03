/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControlKit/FBiOSActionReader.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;

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
