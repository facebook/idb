/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@interface FBiOSTargetFutureDouble : NSObject <FBiOSTargetFuture>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, assign, readonly) BOOL succeed;

- (instancetype)initWithIdentifier:(NSString *)identifier succeed:(BOOL)succeed;

@end
