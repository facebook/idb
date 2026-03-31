/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Commands related to fetching diagnostic information
 */
@protocol FBDiagnosticInformationCommands <NSObject, FBiOSTargetCommand>

/**
 Fetches JSON-Serializable Diagnostic Information

 @return A future that resolves with the Diagnostic Information.
 */
- (nonnull FBFuture<NSDictionary<NSString *, id> *> *)fetchDiagnosticInformation;

@end
