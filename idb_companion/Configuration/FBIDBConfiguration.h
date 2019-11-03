/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBEventReporter;

/**
 Configuration object for idb.
 */
@interface FBIDBConfiguration : NSObject

/**
 The event reporter to use.
 */
@property (nonatomic, strong, readwrite, class) id<FBEventReporter> eventReporter;

@end

NS_ASSUME_NONNULL_END
