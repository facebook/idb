/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcess.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN
@class FBProcessInput;

@protocol FBDataConsumer;

@protocol FBDapServerCommand <NSObject, FBiOSTargetCommand>

- (FBFuture<FBProcess<id, id<FBDataConsumer>, NSString *> *> *) launchDapServer:dapPath stdIn:(FBProcessInput *)stdIn stdOut:(id<FBDataConsumer>)stdOut;

@end

NS_ASSUME_NONNULL_END
