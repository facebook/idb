/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessSpawnConfiguration;

@interface FBArchitectureProcessAdapter : NSObject

/// Force binaries to be launched in desired architectures.
///
/// Convenience method for `-[FBArchitectureProcessAdapter adaptProcessConfiguration:toAnyArchitectureIn:hostArchitectures:queue:temporaryDirectory:]`
-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration toAnyArchitectureIn:(NSSet<FBArchitecture> *)requestedArchitectures queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory;

/// Force binaries to be launched in desired architectures.
///
/// Up to Xcode 14.2, subprocesses were spawned in the same architecture as parent process by default.
/// But from Xcode 14.3, subprocesses are spawned in arm64 when running on a arm64, regardless of parent process architecture.
/// To force subprocess being spawned in other architecture, there is `arch` utility that does not work in simulator context.
///
/// As a workaround, to bring predictability into which architecture spawned process will be spawned,
/// we lipo-thin the executable to an architecture supported by the host machine.
///
/// The selection of the final architecture is done by comparing consiliating the architectures idb companion needs
/// the process to run with (often dictactated by the architecture of the binary code we want to inject into
/// the spawned process) and the architectures supported by the processor of the host machine.
///
/// As an example, on an arm64 machine, when idb companion needs to inject an x86_64 lib into a process that could
/// run in either x86_64 or arm64, the target process needs to be thinned down to `x86_64` to ensure it runs in the
/// same of the lib that needs to be injected.
///
/// - Parameters:
///   - processConfiguration: Initial process configuration
///   - toAnyArchitectureIn: Set of architectures the process needs to be spawned with. `arm64` will take precedence over `x86_64`
///   - queue: Target Queue
///   - hostArchitectures: Set of architectures supported by the host machine
///   - temporaryDirectory: Target directory where we put lipoed binary
-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration toAnyArchitectureIn:(NSSet<FBArchitecture> *)architectures hostArchitectures:(NSSet<FBArchitecture> *)hostArchitectures queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory;


/// Returns supported architectures based on companion launch architecture and launch under rosetta determination.
+(NSSet<FBArchitecture> *)hostMachineSupportedArchitectures;

@end

NS_ASSUME_NONNULL_END
