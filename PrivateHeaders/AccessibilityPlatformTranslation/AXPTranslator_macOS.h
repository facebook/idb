/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AccessibilityPlatformTranslation/AXPTranslator.h>

@interface AXPTranslator_macOS : AXPTranslator
{
    CDUnknownBlockType _zoomTriggerTestingCallback;
    CDUnknownBlockType _appNotificationTestingCallback;
}

+ (id)sharedInstance;
- (void).cxx_destruct;
@property(copy, nonatomic) CDUnknownBlockType appNotificationTestingCallback; // @synthesize appNotificationTestingCallback=_appNotificationTestingCallback;
@property(copy, nonatomic) CDUnknownBlockType zoomTriggerTestingCallback; // @synthesize zoomTriggerTestingCallback=_zoomTriggerTestingCallback;
- (id)processApplicationObject:(id)arg1;
- (id)processFrontMostApp:(id)arg1;
- (id)processHitTest:(id)arg1;
- (id)processAttributeRequest:(id)arg1;
- (id)processActionRequest:(id)arg1;
- (id)processMultipleAttributeRequest:(id)arg1;
- (void)_processAppAccessibilityNotification:(unsigned long long)arg1 data:(id)arg2 associatedObject:(id)arg3;
- (void)_processZoomFocusNotificationWithData:(id)arg1 associatedObject:(id)arg2;
- (CDUnknownBlockType)attributedStringConversionBlock;
- (void)processPlatformNotification:(unsigned long long)arg1 data:(id)arg2 associatedObject:(id)arg3;
- (void)enableAccessibility;
- (id)remotePlatformElementFromTranslation:(id)arg1 forPid:(int)arg2;
- (id)platformElementFromTranslation:(id)arg1;

@end

