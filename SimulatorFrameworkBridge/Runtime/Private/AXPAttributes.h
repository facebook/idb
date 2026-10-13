/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The request kinds `-[AXPTranslator processTranslatorRequest:]` dispatches on, decoded from its jump
 * table. Only the two a reader needs are named. The attribute numbers a request carries are
 * `BridgeAXTranslatorAttribute` in `FBSimulatorBridgeProtocol`, shared with the host.
 */
typedef NS_ENUM(NSInteger, FBAXPRequestType) {
  FBAXPRequestTypeAttribute = 2,
  /** Carries its attribute list under `parameters[@"attributes"]`; the handler forwards the batch to
      `AXUIElementCopyMultipleAttributeValues`. Passing an array rather than that dictionary throws
      inside the guest and takes the reader down with it. */
  FBAXPRequestTypeMultipleAttribute = 5,
};

NS_ASSUME_NONNULL_END
