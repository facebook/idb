/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The attribute vocabulary `AXPTranslator` answers in.
 *
 * Distinct from the `XC_kAXXCAttribute*` names the reader fetches with today, which are XCTest's. Both
 * ultimately reach the same accessibility server — a translator attribute request and an
 * `attributesForElement:` call both bottom out in `AXUIElementCopyMultipleAttributeValues` — but they
 * are separate namespaces with separate server-side handlers, and an element handle from one is not
 * accepted by the other.
 *
 * Values are the enum's own indices, recovered from `__AXPAttributeToString`'s pointer table in the
 * guest `AccessibilityPlatformTranslation` binary: each slot points at a `__CFConstantString` whose
 * `char *` sits at +16, and the slot index is the attribute value. `AXPAttributeChildren` was
 * cross-checked independently against the dispatch jump table in
 * `-[AXPTranslator_iOS _processAttributeSpecialCases:uiElement:parameter:error:client:]`, which routes
 * both 8 and 9 to `_processChildrenAttributeRequest:error:`.
 *
 * Only the members the reader would need are declared. The full enum has 132 members; the rest are
 * omitted rather than transcribed, because an unused constant is one nobody has checked.
 */
typedef NS_ENUM(NSInteger, FBAXPAttribute) {
  FBAXPAttributeClassName = 7,
  FBAXPAttributeChildren = 8,
  FBAXPAttributeChildrenInNavigationOrder = 9,
  FBAXPAttributeContextId = 12,
  FBAXPAttributeCustomActions = 13,
  FBAXPAttributeFrame = 21,
  FBAXPAttributeHelp = 23,
  FBAXPAttributeIdentifier = 25,
  /** No counterpart exists in the `XC_kAXXCAttribute*` namespace, which is why a guest-backed read
      reports `enabled` as an explicit null today. */
  FBAXPAttributeIsEnabled = 27,
  FBAXPAttributeIsVisible = 32,
  FBAXPAttributeLabel = 33,
  FBAXPAttributePlaceholderValue = 42,
  FBAXPAttributeRole = 45,
  FBAXPAttributeSubrole = 51,
  FBAXPAttributeValue = 53,
  FBAXPAttributeIsRemoteElement = 66,
};

/**
 * The request kinds `-[AXPTranslator processTranslatorRequest:]` dispatches on, decoded from its jump
 * table. Only the two a reader needs are named.
 */
typedef NS_ENUM(NSInteger, FBAXPRequestType) {
  FBAXPRequestTypeAttribute = 2,
  /** Carries its attribute list under `parameters[@"attributes"]`; the handler forwards the batch to
      `AXUIElementCopyMultipleAttributeValues`. Passing an array rather than that dictionary throws
      inside the guest and takes the reader down with it. */
  FBAXPRequestTypeMultipleAttribute = 5,
};

NS_ASSUME_NONNULL_END
