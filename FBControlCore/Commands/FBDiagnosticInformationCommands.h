/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands related to fetching diagnostic information
 */
@protocol FBDiagnosticInformationCommands <NSObject, FBiOSTargetCommand>

/**
 Fetches JSON-Serializable Diagnostic Information

 @return A future that resolves with the Diagnostic Information.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)fetchDiagnosticInformation;

@end

NS_ASSUME_NONNULL_END
