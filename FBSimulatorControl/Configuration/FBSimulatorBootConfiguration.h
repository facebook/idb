/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
/**
 An Option Set for Direct Launching.
 */
typedef NS_OPTIONS(NSUInteger, FBSimulatorBootOptions) {
  FBSimulatorBootOptionsTieToProcessLifecycle = 1 << 1, /** When set, will tie the Simulator's lifecycle to that of the launching process. This means that when the process that performs the boot dies, the Simulator is shutdown automatically. */
  FBSimulatorBootOptionsVerifyUsable = 1 << 3, /** A Simulator can be report that it is 'Booted' very quickly but is not in Usable. Setting this option requires that the Simulator is 'Usable' before the boot API completes */
};

NS_ASSUME_NONNULL_BEGIN

/**
 A Value Object for defining how to launch a Simulator.
 */
@interface FBSimulatorBootConfiguration : NSObject <NSCopying>

#pragma mark Properties

/**
 Options for how the Simulator should be launched.
 */
@property (nonatomic, assign, readonly) FBSimulatorBootOptions options;

/**
 The environment used on boot.
 Boot environment is passed down to all launched processes in the Simulator.
 This is useful for injecting a dylib through `DYLD_` environment variables.
 */
@property (nonatomic, nullable, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

#pragma mark Default Instance

/**
 The Default Configuration.
 */
@property (nonatomic, strong, class, readonly) FBSimulatorBootConfiguration *defaultConfiguration;

/**
 The Designated Initializer.
 
 @param options the options to use.
 @param environment the boot environment to use.
 @return a FBSimulatorBootConfiguration instance.
 */
- (instancetype)initWithOptions:(FBSimulatorBootOptions)options environment:(NSDictionary<NSString *, NSString *> *)environment;

@end

NS_ASSUME_NONNULL_END
