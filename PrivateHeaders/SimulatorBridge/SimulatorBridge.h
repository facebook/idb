/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/NSObject.h>

#import "AXPTranslationRuntimeHelper-Protocol.h"
#import "SimulatorBridge-Protocol.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@class CLSimulationManager, NSDistantObject, NSString;
@protocol AccessibilityNotificationUpstream, OS_dispatch_queue;

@interface SimulatorBridge : NSObject <AXPTranslationRuntimeHelper, SimulatorBridge>
{
    _Bool _accessibilityEnabled;
    NSDistantObject<AccessibilityNotificationUpstream> *_accessibilityUpstreamProxy;
    NSObject<OS_dispatch_queue> *_accessibilityUpstreamQueue;
    struct __AXObserver *_axEventObserver;
    CLSimulationManager *_locationSimulationManager;
}

@property(retain, nonatomic) CLSimulationManager *locationSimulationManager; // @synthesize locationSimulationManager=_locationSimulationManager;
@property(nonatomic) struct __AXObserver *axEventObserver; // @synthesize axEventObserver=_axEventObserver;
- (void)sendRemoteButtonInput:(float)arg1 toButtonA:(_Bool)arg2;
- (void)sendGameControllerPausedEvent:(_Bool)arg1;
- (void)sendGameControllerData:(in bycopy id)arg1;
- (void)startListeningForGameControllerClients;
- (void)setLocationWithLatitude:(double)arg1 andLongitude:(double)arg2;
- (void)setLocationScenarioWithPath:(in bycopy id)arg1;
- (void)setLocationScenario:(in bycopy id)arg1;
- (out bycopy id)localizedNameForLocationScenario:(in bycopy id)arg1;
- (out bycopy id)availableLocationScenarios;
- (_Bool)createLocationManager;
- (void)setCADebugOption:(unsigned int)arg1 enabled:(_Bool)arg2;
- (_Bool)getCADebugOption:(unsigned int)arg1;
- (out bycopy id)accessibilityElementForPoint:(double)arg1 andY:(double)arg2 displayId:(unsigned int)arg3;
- (out bycopy id)accessibilityElementsWithDisplayId:(unsigned int)arg1;
- (out bycopy id)updateAccessibilityElement:(id)arg1;
- (id)_convertAXUIElementToDictionary:(struct __AXUIElement *)arg1;
- (_Bool)performDecrementAction:(id)arg1;
- (_Bool)performIncrementAction:(id)arg1;
- (_Bool)performPressAction:(id)arg1;
- (struct __AXUIElement *)_copyElementFromElementDictionary:(id)arg1;
- (void)enableAccessibility;
- (void)_initializeAccessibility;
- (void)handleNotification:(unsigned long long)arg1 data:(id)arg2 associatedObject:(id)arg3;
- (void)setupAccessibilityUpstreamObject;
- (_Bool)requiresAXRuntimeInitialization;
- (_Bool)isSystemWideElement;
- (void)handleScreenChange;
- (id)processPlatformTranslationRequestWithData:(in bycopy id)arg1;
- (void)setHardwareKeyboardEnabled:(_Bool)arg1 keyboardType:(unsigned char)arg2;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) Class superclass;

@end

#pragma GCC diagnostic pop
