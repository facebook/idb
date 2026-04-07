/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

typedef NSString *FBEventType NS_STRING_ENUM;

extern FBEventType _Nonnull const FBEventTypeStarted;
extern FBEventType _Nonnull const FBEventTypeEnded;
extern FBEventType _Nonnull const FBEventTypeDiscrete;
extern FBEventType _Nonnull const FBEventTypeSuccess;
extern FBEventType _Nonnull const FBEventTypeFailure;
