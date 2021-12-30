/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBXCTestShimConfiguration;

/**
 A Value object with the information required to run `xctrace record`
 */
@interface FBXCTraceRecordConfiguration : NSObject <NSCopying>

#pragma mark Initializers

/**
 Create and return a new `xctrace record` configuration with the provided parameters
 */
+ (instancetype)RecordWithTemplateName:(NSString *)templateName
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

- (instancetype)initWithTemplateName:(NSString *)templateName
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
- (instancetype)withShim:(FBXCTestShimConfiguration *)shim;

#pragma mark Properties

/**
 Trace template name or path for recording
 */
@property (nonatomic, copy, readonly) NSString *templateName;

/**
 Limit recording time to the specified value
 */
@property (nonatomic, assign, readonly) NSTimeInterval timeLimit;

/**
 Load Instruments Package from given path for duration of the command
 */
@property (nullable, nonatomic, copy, readonly) NSString *package;

/**
 Record all processes
 */
@property (nonatomic, assign, readonly) BOOL allProcesses;

/**
 Attach and record process with the given name or pid
 */
@property (nullable, nonatomic, copy, readonly) NSString *processToAttach;

/**
 Launch process with the given name or path
 */
@property (nullable, nonatomic, copy, readonly) NSString *processToLaunch;

/**
 The arguments to the target application
 */
@property (nullable, nonatomic, copy, readonly) NSArray<NSString *> *launchArgs;

/**
 Redirect standard input of the launched process
 */
@property (nullable, nonatomic, copy, readonly) NSString *targetStdin;

/**
 Redirect standard output of the launched process
 */
@property (nullable, nonatomic, copy, readonly) NSString *targetStdout;

/**
 Set specified environment variable for the launched process
 */
@property (nullable, nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *processEnv;

/**
 Shim to be applied to xctrace
 */
@property (nonatomic, copy, readonly, nullable) FBXCTestShimConfiguration *shim;

@end

NS_ASSUME_NONNULL_END
