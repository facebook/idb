/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorEventSink.h>

NS_ASSUME_NONNULL_BEGIN

@class FBMutableSimulatorEventSink;
@class FBSimulatorMutableState;
@class FBSimulatorProcessFetcher;

@protocol FBControlCoreLogger;
@protocol FBEventReporter;

@interface FBSimulator ()

@property (nonatomic, strong, readonly) FBSimulatorMutableState *mutableState;
@property (nonatomic, strong, readonly, nullable) FBMutableSimulatorEventSink *mutableSink;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;
@property (nonatomic, strong, readonly) id forwarder;

@property (nonatomic, copy, readwrite) FBSimulatorConfiguration *configuration;

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(nullable FBSimulatorConfiguration *)configuration launchdSimProcess:(nullable FBProcessInfo *)launchdSimProcess containerApplicationProcess:(nullable FBProcessInfo *)containerApplicationProcess set:(FBSimulatorSet *)set;
- (instancetype)initWithDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration set:(FBSimulatorSet *)set processFetcher:(FBSimulatorProcessFetcher *)processFetcher auxillaryDirectory:(NSString *)auxillaryDirectory logger:(nullable id<FBControlCoreLogger>)logger reporter:(nullable id<FBEventReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
