/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorEventSink.h>

@class FBDiagnostic;
@class FBDiagnosticBuilder;
@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 The Name of the Core Simulator Log.
 */
extern FBDiagnosticName const FBDiagnosticNameCoreSimulator;

/**
 The Name of the Simulator Bootstrap.
 */
extern FBDiagnosticName const FBDiagnosticNameSimulatorBootstrap;

/**
 Exposes Simulator Logs & Diagnsotics as FBDiagnostic instances.

 Instances of FBDiagnostic exposed by this class are not nullable since FBDiagnostic's can be empty:
 - This means that values do not have to be checked before storing in collections
 - Missing content can be inserted into the FBDiagnostic instances, whilst retaining the original metadata.
 */
@interface FBSimulatorDiagnostics : FBiOSTargetDiagnostics <FBSimulatorEventSink>

/**
 Creates and returns a `FBSimulatorDiagnostics` instance.

 @param simulator the Simulator to Fetch logs for.
 @return A new `FBSimulatorDiagnostics` instance for the provided Simulator.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

#pragma mark Standard Diagnostics

/**
 The syslog of the Simulator.
 */
- (FBDiagnostic *)syslog;

/**
 The Log for CoreSimulator.
 */
- (FBDiagnostic *)coreSimulator;

/**
 The Bootstrap of the Simulator's launchd_sim.
 */
- (FBDiagnostic *)simulatorBootstrap;

/**
 A Screenshot of the Simulator.
 */
- (FBDiagnostic *)screenshot;

/**
 The 'stdout' diagnostic for a provided Application.
 */
- (FBDiagnostic *)stdOut:(FBProcessLaunchConfiguration *)configuration;

/**
 The 'stderr' diagnostic for a provided Application.
 */
- (FBDiagnostic *)stdErr:(FBProcessLaunchConfiguration *)configuration;

/**
 An Array of all non-empty stderr and stdout logs for launched processes.
 */
- (NSArray<FBDiagnostic *> *)stdOutErrDiagnostics;

@end

NS_ASSUME_NONNULL_END
