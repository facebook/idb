/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBFramebufferConfiguration;

/**
 An Option Set for Direct Launching.
 */
typedef NS_OPTIONS(NSUInteger, FBSimulatorBootOptions) {
  FBSimulatorBootOptionsConnectBridge = 1 << 0, /** Connects the Simulator Bridge on boot, rather than lazily on-demand */
  FBSimulatorBootOptionsEnableDirectLaunch = 1 << 1, /** Launches the Simulator via directly (via SimDevice) instead of with Simulator.app. Enables Framebuffer Connection. */
  FBSimulatorBootOptionsUseNSWorkspace = 1 << 2, /** Uses -[NSWorkspace launchApplicationAtURL:options:configuration::error:] to launch Simulator.app */
  FBSimulatorBootOptionsVerifyUsable = 1 << 3, /** A Simulator can be report that it is 'Booted' very quickly but is not in Usable. Setting this option requires that the Simulator is 'Usable' before the boot API completes */
};

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for a Boot.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeBoot;

/**
 A Value Object for defining how to launch a Simulator.
 */
@interface FBSimulatorBootConfiguration : NSObject <NSCopying, FBiOSTargetFuture, FBDebugDescribeable>

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

/**
 The Locale in which to Simulate, may be nil.
 */
@property (nonatomic, nullable, strong, readonly) FBLocalizationOverride *localizationOverride;

/**
 The Scale of the Framebuffer.
 */
@property (nonatomic, nullable, copy, readonly) FBScale scale;

/**
 Configuration for the Framebuffer.
 If nil, means that the Framebuffer will not be connected on launch
 */
@property (nonatomic, nullable, copy, readonly) FBFramebufferConfiguration *framebuffer;

#pragma mark Default Instance

/**
 The Default Configuration.
 */
@property (nonatomic, strong, class, readonly) FBSimulatorBootConfiguration *defaultConfiguration;

#pragma mark Launch Options

/**
 Updates the boot configuration with new options.

 @param options the options to update.
 @return a new FBSimulatorBootConfiguration with the arguments applied.
 */
- (instancetype)withOptions:(FBSimulatorBootOptions)options;

#pragma mark Environment

/**
 Updates the boot configuration with a new boot environment.

 @param environment the new boot environment.
 @return a new FBSimulatorBootConfiguration with the arguments applied.
 */
- (instancetype)withBootEnvironment:(nullable NSDictionary<NSString *, NSString *> *)environment;

#pragma mark Device Scale

/**
 Updates the boot configuration with a new scale.

 @param scale the scale to update.
 @return a new FBSimulatorBootConfiguration with the arguments applied.
 */
- (instancetype)withScale:(nullable FBScale)scale;

#pragma mark Locale

/**
 Updates the boot configuration with a new localization.

 @param localizationOverride the localization to update.
 @return a new FBSimulatorBootConfiguration with the arguments applied.
 */
- (instancetype)withLocalizationOverride:(nullable FBLocalizationOverride *)localizationOverride;

#pragma mark Framebuffer

/**
 Updates the boot configuration with a new framebuffer configuration.

 @param framebuffer the framebuffer configuration to apply.
 @return a new FBSimulatorBootConfiguration with the arguments applied.
 */
- (instancetype)withFramebuffer:(nullable FBFramebufferConfiguration *)framebuffer;

@end

NS_ASSUME_NONNULL_END
