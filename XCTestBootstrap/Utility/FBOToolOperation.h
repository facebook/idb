/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@interface FBOToolOperation : NSObject

+ (nonnull FBFuture<NSArray<NSString *> *> *)listSanitiserDylibsRequiredByBundle:(nonnull NSString *)testBundlePath onQueue:(nonnull dispatch_queue_t)queue;

@end
