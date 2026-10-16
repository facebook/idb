/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorAX
@testable import FBSimulatorControl
import Foundation
import Testing

/// The mangled inputs here are real `type` values observed on a live read of the Settings root
/// screen — the population this demangler exists for — plus the degenerate shapes the parser must
/// pass through rather than mistranslate.
@Suite
struct SwiftClassNameDemanglerTests {

  @Test
  func plainClassNamesDemangleToTheClassName() {
    #expect(
      SwiftClassNameDemangler.demangle("_TtC5MyApp11MyTestClass") == "MyTestClass"
    )
  }

  @Test
  func nestedClassNamesDemangleToTheInnermostClass() {
    #expect(
      SwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView12BackdropView") == "BackdropView"
    )
    #expect(
      SwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView19LuminanceAdjustment") == "LuminanceAdjustment"
    )
    #expect(
      SwiftClassNameDemangler.demangle("_TtCC5UIKit20ScrollEdgeEffectView10PocketMask") == "PocketMask"
    )
  }

  @Test
  func genericClassNamesDemangleToTheClassNotTheArguments() {
    #expect(
      SwiftClassNameDemangler.demangle("_TtGC7SwiftUI19UIHostingControllerVS_7AnyView_") == "UIHostingController"
    )
    // A multi-parameter generic: the class name is the segment after the module, not the
    // second-to-last segment (which is `_ViewList_View`, an argument).
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtGC7SwiftUI15CellHostingViewGVS_15ModifiedContentVS_14_ViewList_ViewVS_26CollectionViewCellModifier__"
      ) == "CellHostingView"
    )
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtGC7SwiftUI14_UIHostingViewGVS_15ModifiedContentVS_7AnyViewVS_12RootModifier__"
      ) == "_UIHostingView"
    )
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtGC5UIKit22UICorePlatformViewHostGVS_32PlatformViewRepresentableAdaptorVS_33InlineSearchBarViewRepresentation__"
      ) == "UICorePlatformViewHost"
    )
  }

  @Test
  func genericClassScopedByAnAnonymousContextSkipsTheDiscriminator() {
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtGC5UIKitP10$186ea25f022FloatingBarHostingViewVS_20FloatingBarContainer_"
      ) == "FloatingBarHostingView"
    )
  }

  @Test
  func classNestedInsideAGenericClassDemanglesToTheInnermostClass() {
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtCGC7SwiftUI32NavigationStackHostingControllerVS_7AnyView_P10$1d35df01811HostingView"
      ) == "HostingView"
    )
  }

  @Test
  func privateClassNamesDemangleToTheClassNotTheFileDiscriminator() {
    #expect(
      SwiftClassNameDemangler.demangle(
        "_TtC5UIKitP33_F83AB3ECBB2C378B4FCEB681A4D7DB7430UIPlatformGlassInteractionView"
      ) == "UIPlatformGlassInteractionView"
    )
  }

  @Test
  func readableNamesPassThroughUnchanged() {
    for name in ["Button", "StaticText", "Any", "UIButton", "CellHostingView", ""] {
      #expect(SwiftClassNameDemangler.demangle(name) == name)
    }
  }

  @Test
  func unparseableMangledNamesPassThroughUnchanged() {
    // No length-prefixed segments at all.
    #expect(SwiftClassNameDemangler.demangle("_Tt") == "_Tt")
    #expect(SwiftClassNameDemangler.demangle("_TtQq_") == "_TtQq_")
    // Every declared length overruns the string.
    #expect(SwiftClassNameDemangler.demangle("_TtC99Short") == "_TtC99Short")
  }

  @Test
  func overrunningSegmentIsSkippedWithoutLosingTheParsedOnes() {
    // The trailing length claims more characters than remain; the parsed class name still wins.
    #expect(SwiftClassNameDemangler.demangle("_TtC5MyApp7MyClass99") == "MyClass")
  }
}
