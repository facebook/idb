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

/// This approach forcing binaries to be launched in desired architectures.
///
/// By default subprocess spawned by companion has the same architecture as companion itself.
/// To force subprocess being spawned in other architecture, there is `arch` utility that does not work in simulator context.
/// As a workaround, we lipo desired architecture out of the test binary.
/// For example, if idb companion is `arm64`, but test binary is `x86_64`, we need to spawn `x86_64` subprocess.
/// But `xctest` binary that wraps test execution has both `x86_64` and `arm64` and when we launch it, it catches companion's `arm64` architecture
/// and as a result, can not open test binary inside itself because of mismatched architecture. To address that problem, we lipoing out only `x86_64` arch from `xctest`
/// and spawning it, making tests work as expected.
/// - Parameters:
///   - processConfiguration: Initial process configuration
///   - architectures: Available architectures of binary under test
///   - queue: Target Queue
///   - temporaryDirectory: Target directory where we put lipoed binary
-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration availableArchitectures:(NSSet<FBArchitecture> *)architectures queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory;

/// This approach forcing binaries to be launched in desired architectures.
/// 
/// By default subprocess spawned by companion has the same architecture as companion itself.
/// To force subprocess being spawned in other architecture, there is `arch` utility that does not work in simulator context.
/// As a workaround, we lipo desired architecture out of the test binary.
/// For example, if idb companion is `arm64`, but test binary is `x86_64`, we need to spawn `x86_64` subprocess.
/// But `xctest` binary that wraps test execution has both `x86_64` and `arm64` and when we launch it, it catches companion's `arm64` architecture
/// and as a result, can not open test binary inside itself because of mismatched architecture. To address that problem, we lipoing out only `x86_64` arch from `xctest`
/// and spawning it, making tests work as expected.
/// - Parameters:
///   - processConfiguration: Initial process configuration
///   - architectures: Available architectures of binary under test
///   - compatibleArchitecture: Architecture that binary will be lipoed to if available architectures do not contain one
///   - queue: Target Queue
///   - temporaryDirectory: Target directory where we put lipoed binary
-(FBFuture<FBProcessSpawnConfiguration *> *)adaptProcessConfiguration:(FBProcessSpawnConfiguration *)processConfiguration availableArchitectures:(NSSet<FBArchitecture> *)architectures compatibleArchitecture:(FBArchitecture)compatibleArchitecture queue:(dispatch_queue_t)queue temporaryDirectory:(NSURL *)temporaryDirectory;

@end

NS_ASSUME_NONNULL_END
