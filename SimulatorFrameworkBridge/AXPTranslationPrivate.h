/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for the AccessibilityPlatformTranslation private API.
//
// AXPTranslator is what resolves the window server's own notion of the frontmost application. It is
// normally driven from the host, which services each per-element request the translator emits over
// CoreSimulator; in-guest the loop is closed locally by handing the translator a bridge delegate that
// routes every request straight back into the translator's own processTranslatorRequest:.
//
// The framework is dlopen-loaded from the booted runtime root and its class resolved with
// objc_lookUpClass, so nothing here is referenced at link time. The declarations exist so the messages
// sent to the translator are checked by the compiler rather than hand-cast through objc_msgSend.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The framework's path inside the booted runtime root, for dlopen. */
#define FBAXPathAXPTranslation \
        "/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework/AccessibilityPlatformTranslation"

/**
 * The block the translator calls to service one request against the platform it is translating for.
 * Returning nil answers "no result", which the translator tolerates.
 */
typedef id _Nullable (^AXPTranslationBridgeCallback)(id request);

/**
 * The bridge delegate an AXPTranslator services its per-element requests through. Held **weakly** by
 * the translator, so a delegate must be retained by whoever installs it.
 */
@protocol AXPTranslationTokenDelegateHelper <NSObject>

/** The request-servicing callback, for a translator that supports delegate tokens. */
- (nullable AXPTranslationBridgeCallback)accessibilityTranslationDelegateBridgeCallbackWithToken:(NSString *)token;

/** The request-servicing callback, for a translator that does not. */
- (nullable AXPTranslationBridgeCallback)accessibilityTranslationDelegateBridgeCallback;

/** Maps a frame from the translated platform's coordinate space into the system's. */
- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect withToken:(NSString *)token;

/** Maps a frame from the translated platform's coordinate space into the system's. */
- (CGRect)accessibilityTranslationConvertPlatformFrameToSystem:(CGRect)rect;

/** The element to graft the translated tree under, or nil to leave it rootless. */
- (nullable id)accessibilityTranslationRootParentWithToken:(NSString *)token;

/** The element to graft the translated tree under, or nil to leave it rootless. */
- (nullable id)accessibilityTranslationRootParent;

@end

/**
 * A translated element or application. Only the owning process is read from it here.
 */
@interface AXPTranslationObject : NSObject

@property (nonatomic) pid_t pid;

@end

/**
 * The platform accessibility translator. The iOS instance is the one that answers against the guest's
 * own window server.
 */
@protocol AXPTranslatorClass;

/**
 * One request to the translator. `requestType` selects the kind (see `FBAXPRequestType`); `attributeType`
 * names a single attribute for an attribute request; `parameters` carries everything else.
 *
 * A multiple-attribute request passes its list as `parameters[@"attributes"]`. **The handler subscripts
 * `parameters` by key** — passing an array in its place raises inside the guest and takes the reader
 * process down with it.
 */
@interface AXPTranslatorRequest : NSObject

/** Addresses the element the request is about. */
+ (nullable instancetype)requestWithTranslation:(id)translation;

@property (nonatomic, assign) NSUInteger requestType;
@property (nonatomic, assign) NSUInteger attributeType;
@property (nullable, nonatomic, strong) id parameters;

@end

/** The answer to one request. `resultData` is nil when the translator could not answer. */
@interface AXPTranslatorResponse : NSObject

@property (nullable, nonatomic, strong) id resultData;

@end

@interface AXPTranslator : NSObject

/** The process-wide iOS translator. */
+ (nullable instancetype)sharediOSInstance;

/**
 * The application the window server considers frontmost on `displayId`, or nil if it cannot say.
 *
 * Resolving this emits per-element requests through `bridgeTokenDelegate`, so a translator with no
 * delegate installed answers nil.
 */
- (nullable AXPTranslationObject *)frontmostApplicationWithDisplayId:(unsigned int)displayId
                                                 bridgeDelegateToken:(NSString *)token;

/** Resolves one translator request against the local AX server. This is what a bridge callback calls. */
- (nullable AXPTranslatorResponse *)processTranslatorRequest:(AXPTranslatorRequest *)request;

/**
 * Wraps an `AXUIElementRef` as the translation object a request addresses.
 *
 * **Borrows** the reference: the returned object does not extend its lifetime, so the caller must keep
 * the ref alive for as long as it uses the translation.
 */
- (nullable id)translationObjectFromPlatformElement:(void *)element;

/** The bridge delegate, held **weakly** — an installed delegate must be retained elsewhere. */
@property (nullable, nonatomic, weak) id<AXPTranslationTokenDelegateHelper> bridgeTokenDelegate;

/** Whether the translator passes a token to its bridge delegate. */
@property (nonatomic) BOOL supportsDelegateTokens;

@end

/**
 * The class-side interface, for messaging a class resolved with `objc_lookUpClass`.
 *
 * A `Class` carries no type, so a send to one is resolved against whatever declaration in the translation
 * unit happens to share the selector — which is the wrong class's declaration as easily as the right one.
 * Casting the looked-up class to `Class<AXPTranslatorClass>` names the declaration to check against.
 */
@protocol AXPTranslatorClass <NSObject>
+ (nullable AXPTranslator *)sharediOSInstance;
@end

NS_ASSUME_NONNULL_END
