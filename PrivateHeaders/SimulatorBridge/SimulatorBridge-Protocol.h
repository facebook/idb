/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSArray, NSData, NSDictionary, NSString;

@protocol SimulatorBridge <NSObject>
- (void)setLocationWithLatitude:(double)arg1 andLongitude:(double)arg2;
- (void)setLocationScenarioWithPath:(in bycopy NSString *)arg1;
- (void)setLocationScenario:(in bycopy NSString *)arg1;
- (out bycopy NSString *)localizedNameForLocationScenario:(in bycopy NSString *)arg1;
- (out bycopy NSArray *)availableLocationScenarios;
- (void)setCADebugOption:(unsigned int)arg1 enabled:(_Bool)arg2;
- (_Bool)getCADebugOption:(unsigned int)arg1;
- (out bycopy NSDictionary *)accessibilityElementForPoint:(double)arg1 andY:(double)arg2 displayId:(unsigned int)arg3;
- (out bycopy NSArray *)accessibilityElementsWithDisplayId:(unsigned int)arg1;
- (out bycopy NSDictionary *)updateAccessibilityElement:(NSDictionary *)arg1;
- (_Bool)performIncrementAction:(NSDictionary *)arg1;
- (_Bool)performDecrementAction:(NSDictionary *)arg1;
- (_Bool)performPressAction:(NSDictionary *)arg1;
- (NSData *)processPlatformTranslationRequestWithData:(in bycopy NSData *)arg1;
- (void)sendRemoteButtonInput:(float)arg1 toButtonA:(_Bool)arg2;
- (void)sendGameControllerPausedEvent:(_Bool)arg1;
- (void)sendGameControllerData:(in bycopy NSData *)arg1;
- (void)startListeningForGameControllerClients;
- (void)setHardwareKeyboardEnabled:(_Bool)arg1 keyboardType:(unsigned char)arg2;

@optional
// Available in Xcode 10.
- (void)enableAccessibility;
// Removed in Xcode 10.
@property BOOL accessibilityEnabled;

@end

