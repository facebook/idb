/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Defines a Full and Partial Description of the receiver
 Bridges to Swift's CustomDebugStringConvertible.
 */
@protocol FBDebugDescribeable

/**
 A Full Description of the receiver.
 */
@property (nonatomic, readonly, copy) NSString *debugDescription;

/**
 A Partial Description of the receiver.
 */
@property (nonatomic, readonly, copy) NSString *shortDescription;

@end

NS_ASSUME_NONNULL_END
