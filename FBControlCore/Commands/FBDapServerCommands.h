/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBSubprocess.h>

@class FBProcessInput;

@protocol FBDataConsumer;

@protocol FBDapServerCommand <NSObject, FBiOSTargetCommand>

- (nonnull FBFuture<FBSubprocess<id, id<FBDataConsumer>, NSString *> *> *)launchDapServer:dapPath stdIn:(nonnull FBProcessInput *)stdIn stdOut:(nonnull id<FBDataConsumer>)stdOut;

@end
