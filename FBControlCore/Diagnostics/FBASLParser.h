/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBDiagnostic;
@class FBDiagnosticBuilder;
@class FBProcessInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 Reads ASL Messages using asl(3).
 */
@interface FBASLParser : NSObject

/**
 Creates and returns a new ASL Parser.
 */
+ (nullable instancetype)parserForPath:(NSString *)path;

/**
 Returns a FBDiagnostic for the log messages relevant to the provided process info.

 @param processInfo the Process Info to obtain filtered log information.
 @param logBuilder the log builder to base the log off.
 @return an FBDiagnostic populated with log lines for the provided process.
 */
- (FBDiagnostic *)diagnosticForProcessInfo:(FBProcessInfo *)processInfo logBuilder:(FBDiagnosticBuilder *)logBuilder;

@end

NS_ASSUME_NONNULL_END
