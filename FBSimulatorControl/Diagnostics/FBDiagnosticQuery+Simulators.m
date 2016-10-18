/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDiagnosticQuery+Simulators.h"

#import "FBSimulatorDiagnostics.h"

@implementation FBDiagnosticQuery_All (Simulators)

- (nonnull NSArray<FBDiagnostic *> *)perform:(nonnull FBSimulatorDiagnostics *)diagnostics
{
  return [diagnostics allDiagnostics];
}

@end

@implementation FBDiagnosticQuery_Named (Simulators)

- (nonnull NSArray<FBDiagnostic *> *)perform:(nonnull FBSimulatorDiagnostics *)diagnostics
{
  return [[[diagnostics namedDiagnostics]
    objectsForKeys:self.names notFoundMarker:(id)NSNull.null]
    filteredArrayUsingPredicate:NSPredicate.notNullPredicate];
}

@end

@implementation FBDiagnosticQuery_ApplicationLogs (Simulators)

- (nonnull NSArray<FBDiagnostic *> *)perform:(nonnull FBSimulatorDiagnostics *)diagnostics
{
  return [diagnostics diagnosticsForApplicationWithBundleID:self.bundleID withFilenames:self.filenames fallbackToGlobalSearch:YES];
}

@end

@implementation FBDiagnosticQuery_Crashes (Simulators)

- (nonnull NSArray<FBDiagnostic *> *)perform:(nonnull FBSimulatorDiagnostics *)diagnostics
{
  return [diagnostics subprocessCrashesAfterDate:self.date withProcessType:self.processType];
}

@end

@implementation FBDiagnosticQuery (Simulators)

- (nonnull NSArray<FBDiagnostic *> *)perform:(nonnull FBSimulatorDiagnostics *)diagnostics
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return @[];
}

@end
