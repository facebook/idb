/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import "FBIDBCompanionServer.h"


NS_ASSUME_NONNULL_BEGIN

@class FBIDBCommandExecutor;
@class FBIDBPortsConfiguration;

/**
 A companion in grpc.
 */
@interface FBGRPCServer : NSObject <FBIDBCompanionServer>

@end

NS_ASSUME_NONNULL_END
