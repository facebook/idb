/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessInfo;
@class FBSimulator;

/**
 Protocol for interacting with a Simulator's launchctl
 */
@protocol FBSimulatorLaunchCtlCommands <NSObject, FBiOSTargetCommand>

#pragma mark Querying Services

/**
 Finds the Service Name for a provided process identifier
 Will fail if there is no process matching the Process Info found.

 @param pid the process identifier to obtain the name for.
 @return A Future, wrapping the Service Name.
 */
- (FBFuture<NSString *> *)serviceNameForProcessIdentifier:(pid_t)pid;

/**
 Finds the Service Name for a provided process.
 Will fail if there is no process matching the Process Info found.

 @param process the process to obtain the name for.
 @return A Future, wrapping the Service Name.
 */
- (FBFuture<NSString *> *)serviceNameForProcess:(FBProcessInfo *)process;

/**
 Finds the Service Name and Process Identifier for all services matching the given search pattern.

 @param regex a regular expression used to match.
 @return A Future, wrapping a mapping of Service Names to Process Identifiers.
 */
- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)serviceNamesAndProcessIdentifiersMatching:(NSRegularExpression *)regex;

/**
 Finds the Service Name and Process Identifier for the first service matching the given search pattern.

 @param regex a Substring of the Service to fetch.
 @return A Future, wrapping a tuple of String Service Name & NSNumber Process Identifier.
 */
- (FBFuture<NSArray<id> *> *)firstServiceNameAndProcessIdentifierMatching:(NSRegularExpression *)regex;

/**
 Consults the Simulator's launchctl to determine the existence of a given process.

 @param process the process to look for.
 @return A Future, YES if the process exists. NO otherwise.
 */
- (FBFuture<NSNumber *> *)processIsRunningOnSimulator:(FBProcessInfo *)process;

/**
 Returns the currently running launchctl services.
 Returns a Mapping of Service Name to Process Identifier.
 NSNull is used to represent services that do not have a Process Identifier.

 @return A Future, wrapping a Mapping of Service Name to Process identifier.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)listServices;

#pragma mark Manipulating Services

/**
 Stops the Provided Process, by Service Name.

 @param serviceName the name of the Process to Stop.
 @return A Future, wrapping the Service Name of the Stopped process, or nil if the process does not exist.
 */
- (FBFuture<NSString *> *)stopServiceWithName:(NSString *)serviceName;

/**
 Starts the Provided Process, by Service Name.

 @param serviceName the name of the Process to Stop.
 @return A Future, wrapping the Service Name of the Stopped process, or nil if the process does not exist.
 */
- (FBFuture<NSString *> *)startServiceWithName:(NSString *)serviceName;

@end

/**
 An Interface to a Simulator's launchctl.
 */
@interface FBSimulatorLaunchCtlCommands : NSObject <FBSimulatorLaunchCtlCommands>

#pragma mark Helpers

/**
 Extracts the Bundle Identifier from a Service Name.

 @param serviceName the service name to extract from
 @return the Bundle ID, if found.
 */
+ (nullable NSString *)extractApplicationBundleIdentifierFromServiceName:(NSString *)serviceName;

@end

NS_ASSUME_NONNULL_END
