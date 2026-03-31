/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBXCTestShimConfiguration;

/**
 A Value object with the information required to run `xctrace record`
 */
@interface FBXCTraceRecordConfiguration : NSObject <NSCopying>

#pragma mark Initializers

/**
 Create and return a new `xctrace record` configuration with the provided parameters
 */
+ (nonnull instancetype)RecordWithTemplateName:(nonnull NSString *)templateName
                                     timeLimit:(NSTimeInterval)timeLimit
                                       package:(nullable NSString *)package
                                  allProcesses:(BOOL)allProcesses
                               processToAttach:(nullable NSString *)processToAttach
                               processToLaunch:(nullable NSString *)processToLaunch
                                    launchArgs:(nullable NSArray<NSString *> *)launchArgs
                                   targetStdin:(nullable NSString *)targetStdin
                                  targetStdout:(nullable NSString *)targetStdout
                                    processEnv:(nullable NSDictionary<NSString *, NSString *> *)processEnv
                                          shim:(nullable FBXCTestShimConfiguration *)shim;

- (nonnull instancetype)initWithTemplateName:(nonnull NSString *)templateName
                                   timeLimit:(NSTimeInterval)timeLimit
                                     package:(nullable NSString *)package
                                allProcesses:(BOOL)allProcesses
                             processToAttach:(nullable NSString *)processToAttach
                             processToLaunch:(nullable NSString *)processToLaunch
                                  launchArgs:(nullable NSArray<NSString *> *)launchArgs
                                 targetStdin:(nullable NSString *)targetStdin
                                targetStdout:(nullable NSString *)targetStdout
                                  processEnv:(nullable NSDictionary<NSString *, NSString *> *)processEnv
                                        shim:(nullable FBXCTestShimConfiguration *)shim;
/**
 Add shim to xctrace

 @param shim shim to be applied to xctrace
 @return new xctrace record config with shim added
 */
- (nonnull instancetype)withShim:(nonnull FBXCTestShimConfiguration *)shim;

#pragma mark Properties

/**
 Trace template name or path for recording
 */
@property (nonnull, nonatomic, readonly, copy) NSString *templateName;

/**
 Limit recording time to the specified value
 */
@property (nonatomic, readonly, assign) NSTimeInterval timeLimit;

/**
 Load Instruments Package from given path for duration of the command
 */
@property (nullable, nonatomic, readonly, copy) NSString *package;

/**
 Record all processes
 */
@property (nonatomic, readonly, assign) BOOL allProcesses;

/**
 Attach and record process with the given name or pid
 */
@property (nullable, nonatomic, readonly, copy) NSString *processToAttach;

/**
 Launch process with the given name or path
 */
@property (nullable, nonatomic, readonly, copy) NSString *processToLaunch;

/**
 The arguments to the target application
 */
@property (nullable, nonatomic, readonly, copy) NSArray<NSString *> *launchArgs;

/**
 Redirect standard input of the launched process
 */
@property (nullable, nonatomic, readonly, copy) NSString *targetStdin;

/**
 Redirect standard output of the launched process
 */
@property (nullable, nonatomic, readonly, copy) NSString *targetStdout;

/**
 Set specified environment variable for the launched process
 */
@property (nullable, nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *processEnv;

/**
 Shim to be applied to xctrace
 */
@property (nullable, nonatomic, readonly, copy) FBXCTestShimConfiguration *shim;

@end
