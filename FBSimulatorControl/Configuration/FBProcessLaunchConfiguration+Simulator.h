/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 Process Launch Configuration for Simulators.
 */
@interface FBProcessLaunchConfiguration (Simulator)

/**
 Creates a FBDiagnostic for the location of the stdout, if applicable.

 @param simulator the simulator to create the diagnostic for.
 @param diagnosticOut an outparam for the diagnostic.
 @param error an error out for any error that occurs.
 @return a diagnostic if applicable, nil otherwise.
 */
- (BOOL)createStdOutDiagnosticForSimulator:(FBSimulator *)simulator diagnosticOut:(FBDiagnostic *_Nullable * _Nullable)diagnosticOut error:(NSError **)error;

/**
 Creates a FBDiagnostic for the location of the stderr, if applicable.

 @param simulator the simulator to create the diagnostic for.
 @param diagnosticOut an outparam for the diagnostic.
 @param error an error out for any error that occurs.
 @return a diagnostic if applicable, nil otherwise.
 */
- (BOOL)createStdErrDiagnosticForSimulator:(FBSimulator *)simulator diagnosticOut:(FBDiagnostic *_Nullable* _Nullable)diagnosticOut error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
