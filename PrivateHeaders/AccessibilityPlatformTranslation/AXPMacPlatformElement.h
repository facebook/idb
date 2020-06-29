/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class AXPTranslationObject, NSArray, NSMutableDictionary, NSString;
@protocol NSAccessibilityCustomElementDataProvider, AXPTranslationElementProtocol;

@interface AXPMacPlatformElement : NSAccessibilityElement
{
    NSMutableDictionary *_selectiveCache;
    AXPTranslationObject *translation;
    CDUnknownBlockType _nsPostEventTestingCallback;
    NSArray *_cachedCustomActions;
    NSArray *_cachedCustomRotors;
}

+ (id)elementWithAccessibilityCustomElementData:(id)arg1;
+ (id)applicationElement;
+ (void)initialize;
+ (id)platformElementWithTranslationObject:(id)arg1;
@property(retain, nonatomic) NSArray *cachedCustomRotors; // @synthesize cachedCustomRotors=_cachedCustomRotors;
@property(retain, nonatomic) NSArray *cachedCustomActions; // @synthesize cachedCustomActions=_cachedCustomActions;
@property(copy, nonatomic) CDUnknownBlockType nsPostEventTestingCallback; // @synthesize nsPostEventTestingCallback=_nsPostEventTestingCallback;
@property(retain, nonatomic) AXPTranslationObject *translation; // @synthesize translation;
@property(readonly, copy) NSString *description;
- (void)dealloc;
- (BOOL)accessibilityShouldUseUniqueId;
- (void)accessibilityPerformAction:(id)arg1;
- (void)performScrollRightByPageAction;
- (void)performScrollLeftByPageAction;
- (void)performScrollUpByPageAction;
- (void)performScrollDownByPageAction;
- (void)performDecrementAction;
- (void)performIncrementAction;
- (BOOL)performEscapeAction;
- (void)performScrollToVisible;
- (BOOL)_synthesizeMouseClick:(unsigned int)arg1;
- (unsigned int)_windowContextId;
- (int)_remoteElementPid;
- (BOOL)_clientSideRemoteElement;
- (BOOL)_isRemoteElement;
- (id)_convertTranslatorResponse:(id)arg1 forAttribute:(unsigned long long)arg2;
- (id)_convertTranslatorResponseForSubrole:(id)arg1;
- (id)_convertTranslatorResponseForRole:(id)arg1;
- (void)_cacheResultSelectively:(id)arg1 attribute:(unsigned long long)arg2;
- (id)_postProcessAttributedString:(id)arg1;
- (BOOL)_shouldPostProcessSubstituteRemoteRepresentationWithObject:(id)arg1 forAttribute:(unsigned long long)arg2;
- (id)_postProcessResult:(id)arg1 attributeType:(unsigned long long)arg2;
- (id)_accessibilityProcessAttribute:(id)arg1 parameter:(id)arg2;
- (id)_accessibilityProcessAttribute:(id)arg1;
- (id)_accessibilityProcessImmediateAttributeResult:(id)arg1;
- (id)_accessibilityTranslationRootParent;
- (BOOL)accessibilitySupportsCustomElementData;
- (id)accessibilityCustomElementData;
- (BOOL)isEqual:(id)arg1;
//@property(readonly) unsigned long long hash;
- (id)accessibilityAttributeValue:(NSAccessibilityAttributeName)arg1;
- (void)setAccessibilityValue:(id)arg1;
- (int)accessibilityPresenterProcessIdentifier;
- (id)accessibilityValue;
- (id)accessibilityLabel;
- (id)accessibilityTitle;
- (id)accessibilityParent;
- (struct CGRect)accessibilityFrame;
- (struct CGPoint)accessibilityActivationPoint;
- (NSDictionary<NSString *, id> *)accessibilityMultipleAttributes:(NSArray<NSAccessibilityAttributeName> *)arg1; // Takes a NSAccessibilityAttributeName and returns a dictionary mapping it to values
- (id)accessibilityAttributeValue:(id)arg1 forParameter:(id)arg2;
- (unsigned long long)_attributeTypeForMacAttribute:(id)arg1;
- (id)_macAttributeTypeForAXPAttribute:(unsigned long long)arg1;
- (BOOL)accessibilityIsAttributeSettable:(id)arg1;
- (void)accessibilitySetValue:(id)arg1 forAttribute:(id)arg2;
- (id)accessibilityActionDescription:(id)arg1;
- (BOOL)accessibilityIsIgnored;
- (id)accessibilityHitTest:(struct CGPoint)arg1 withDisplayId:(unsigned int)arg2;
- (id)accessibilityHitTest:(struct CGPoint)arg1;
- (int)pid;
- (id)accessibilityActionNames;
- (id)accessibilityCustomActions;
- (id)accessibilityCustomRotors;
- (id)_customRotorData:(id)arg1;
- (id)rotor:(id)arg1 resultForSearchParameters:(id)arg2;
- (id)accessibilityParameterizedAttributeNames;
- (id)accessibilityAttributeNames;
- (BOOL)accessibilityPerformPress;
- (BOOL)accessibilityPerformShowMenu;
- (id)accessibilityRole;
- (id)role;
- (id)_cachedRole;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly) Class superclass;

@end

