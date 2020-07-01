/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class AXPTranslationObject;
@class AXPTranslatorResponse;
@class AXPTranslatorRequest;

/**
 The return type of the translation callbacks, this will synchronously provide a response by calling out to CoreSimulator.
 */
typedef AXPTranslatorResponse * (^AXPTranslationCallback)(AXPTranslatorRequest *request);

@protocol AXPTranslationDelegateHelper

/**
 This function is used by AXPTranslator through delegation. Upon requesting additional fields for a given AXPMacPlatformElement.
 The implementation of this function calls out the the underlying API to obtain a AXPTranslatorResponse for a given AXPTranslatorRequest.
 The call is synchronous and the CoreSimulator API is asynchronous, so this needs to operate on a background queue that can block.
 */
 - (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallback;

/**
 This is used in the construction of Mac accessibility objects.
 It's the job of this function to translate co-ordinate spaces.
 This is mostly relevant for Simulator.app where AppKit has a different co-ordinate space to UIKit.
 */
 - (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withContext:(id)context postProcess:(id)postProcess;

/**
 Used to obtain the parent of an accessibility component.
 Unknown how this is implemented.
 */
 - (id)accessibilityTranslationRootParent;

@end

@protocol AXPTranslationTokenDelegateHelper

/**
 This is the same as the above, except requests can be tokenized.
 */
- (AXPTranslationCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token;

/**
 The same as above, except tokenized.
 */
- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token;

/**
 Used to obtain the parent of an accessibility component, except tokenized.
 Unknown how this is implemented.
 */
- (id)accessibilityTranslationRootParentWithToken:(NSString *)token;

@end;

@protocol AXPTranslationRuntimeHelper, AXPTranslationSystemAppDelegate;

@interface AXPTranslator : NSObject
{
    BOOL _accessibilityEnabled;
    BOOL _supportsDelegateTokens;
    id <AXPTranslationDelegateHelper> _bridgeDelegate;
    id <AXPTranslationTokenDelegateHelper> _bridgeTokenDelegate;
    id <AXPTranslationRuntimeHelper> _runtimeDelegate;
    id <AXPTranslationSystemAppDelegate> _systemAppDelegate;
    NSMutableDictionary *_fakeElementCache;
}

+ (id)sharedmacOSInstance;
+ (id)sharediOSInstance;
+ (id)sharedInstance;
@property(nonatomic) BOOL supportsDelegateTokens; // @synthesize supportsDelegateTokens=_supportsDelegateTokens;
@property(retain, nonatomic) NSMutableDictionary *fakeElementCache; // @synthesize fakeElementCache=_fakeElementCache;
@property(nonatomic) __weak id <AXPTranslationSystemAppDelegate> systemAppDelegate; // @synthesize systemAppDelegate=_systemAppDelegate;
@property(nonatomic) __weak id <AXPTranslationRuntimeHelper> runtimeDelegate; // @synthesize runtimeDelegate=_runtimeDelegate;
@property(nonatomic) __weak id <AXPTranslationTokenDelegateHelper> bridgeTokenDelegate; // @synthesize bridgeTokenDelegate=_bridgeTokenDelegate;
@property(nonatomic) __weak id <AXPTranslationDelegateHelper> bridgeDelegate; // @synthesize bridgeDelegate=_bridgeDelegate;
@property(nonatomic) BOOL accessibilityEnabled; // @synthesize accessibilityEnabled=_accessibilityEnabled;
- (id)remoteTranslationDataWithTranslation:(id)arg1 pid:(int)arg2;
- (id)translationObjectFromData:(id)arg1;
- (id)platformElementFromTranslation:(id)arg1;
- (void)initializeAXRuntimeForSystemAppServer;
- (void)enableAccessibility;
- (void)processPlatformNotification:(unsigned long long)arg1 data:(id)arg2;
- (CDUnknownBlockType)attributedStringConversionBlock;
- (id)processSupportedActions:(id)arg1;
- (id)processFrontMostApp:(id)arg1;
- (id)processHitTest:(id)arg1;
- (id)processAttributeRequest:(id)arg1;
- (id)processCanSetAttribute:(id)arg1;
- (id)processSetAttribute:(id)arg1;
- (id)processActionRequest:(id)arg1;
- (id)processMultipleAttributeRequest:(id)arg1;
- (id)appKitPlatformElementFromTranslation:(id)arg1;
- (id)macPlatformElementFromTranslation:(id)arg1;
- (AXPTranslationObject *)objectAtPoint:(struct CGPoint)arg1 displayId:(unsigned int)arg2 bridgeDelegateToken:(id)arg3;
- (id)processTranslatorRequest:(id)arg1;
- (id)platformTranslator;
- (id)sendTranslatorRequest:(id)arg1;
- (void)_resetBridgeTokensForResponse:(id)arg1 bridgeDelegateToken:(id)arg2;
- (void)handleNotification:(unsigned long long)arg1 data:(id)arg2 associatedObject:(id)arg3;
- (AXPTranslationObject *)frontmostApplicationWithDisplayId:(unsigned int)arg1 bridgeDelegateToken:(NSString *)arg2;
- (id)_translationApplicationObjectForPidNumber:(id)arg1;
- (id)translationApplicationObjectForPid:(int)arg1;
- (id)translationApplicationObject;
- (id)init;

@end

