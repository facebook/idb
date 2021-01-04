/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBEventReporter.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;
@protocol FBEventReporter;
@protocol FBiOSTarget;
@protocol FBiOSTargetOperation;

/**
 An extensible string enum representing an Action Type.
 */
typedef NSString *FBiOSTargetOperationType NS_EXTENSIBLE_STRING_ENUM;

/**
 The Action Type for an Application Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeApplicationLaunch;

/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeAgentLaunch;

/**
 The Action Type for a Test Launch.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeTestLaunch;

/**
 The Action Type for Log Tails.
 */
extern FBiOSTargetOperationType const FBiOSTargetOperationTypeLogTail;

/**
 A protocol that represents an operation of indeterminate length.
 */
@protocol FBiOSTargetOperation <NSObject>

/**
 A Optional Future that resolves when the operation has completed.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *completed;

@end

/**
 Creates a new operation.

 @param completed the completion future
 @return an Operation wrapping the Future
 */
extern id<FBiOSTargetOperation> FBiOSTargetOperationFromFuture(FBFuture<NSNull *> *completed);

NS_ASSUME_NONNULL_END
