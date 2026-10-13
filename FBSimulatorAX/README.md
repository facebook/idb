# FBSimulatorAX

Reads and drives the accessibility tree of an iOS Simulator's frontmost application, without a test bundle. It is the Simulator's accessibility capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not read accessibility does not link it.

It holds the accessibility model its readers answer with, and builds on `FBSimulatorControl`, whose display routing and guest bridge it reads through, and on [`FBSimulatorBridgeProtocol`](../FBSimulatorBridgeProtocol/README.md), the vocabulary it and the in-guest reader share.

## Reading the tree

`Simulator.uiAutomation(backend:display:)` returns a `UIAutomation`: one query-shaped surface for element reads (`describe`, `wait`, `quiescence`) and element-targeted actions (`tap`, `scroll`, `setValue`, `drag`). The backend decides how the tree is read.

- **`.accessibility`** translates the frontmost application's tree on the host, through the private `AccessibilityPlatformTranslation` framework that `Simulator.app` uses. It reaches only the active display. Each element's attributes are fetched in one multiple-attribute request rather than one request per attribute; `AccessibilityRequestOptions.translatorReads` selects the per-attribute reads instead. Requests go straight to `com.apple.CoreSimulator.accessibility`, the service CoreSimulatorBridge vends inside the simulator, over one connection held per simulator; when that service cannot be reached they go through CoreSimulator's own client to the same service.
- **`.axBridge`** reads in the guest, at XCUITest fidelity, through the `SimulatorFrameworkBridge` helper that `FBSimulatorControl` runs inside the booted Simulator. Its persistence chooses which guest serves the read:
  - `.oneShot` spawns a guest per read. It holds nothing, so it costs nothing to reconstruct.
  - `.shared` reads over the Simulator's well-known socket, shared with every other process reading the same Simulator. The connection is released after each round trip so the next reader can have it, and only the guest's own idle timeout ends it.
  - `.exclusive` reads over a guest of the caller's own, on a socket nobody else can discover, and holds its connection between reads. The guest exits when that connection closes, so it suits a process that owns the Simulator for its lifetime.

A read can claim a requesting client (`AccessibilityRequestOptions.clientType`), which decides what the application answers with: the automation tree for clients such as `xctest`, the flattened VoiceOver tree for the rest. The client is carried by translator requests only. On `.accessibility` that is every request a read makes; on `.axBridge` it is the `semantic` traversal, which the automatic traversal selects when a client is named, and display hit-tests. An explicit XCTest-vocabulary traversal with a client is refused rather than ignored. Actions, frames and waits take no options and claim the client a default read resolves to.

Operations reach the display a `DisplaySelection` names and fail rather than reach another; see the multiple displays section of [the `FBSimulatorControl` README](../FBSimulatorControl/README.md).

## The accessibility model

Every reader produces the same model, so a consumer can use one result regardless of which backend read it.

- **Requests.** `AccessibilityRequestOptions` gathers what a read asks for: which `AXKeys` to report, an `AccessibilityElementFilter` such as interactable-only, an `AccessibilityMatch` substring search, the traversal (`AXTraversal`, the bridge protocol's `BridgeAXTraversal`), the requesting client (`AXClientType`, resolved through `resolvedClientType` so a read that names none claims none), whether to explain unreachable elements, and how to read remote content such as web views, which live in separate processes and need grid-based hit-testing.
- **Keys.** `AXKeys` names every attribute a read can report. Their raw values are the JSON keys in idb's output and the cli's `--key` names, so they are stable. `AXSearchableKey` is the subset with string values that a search can match against.
- **Documents.** `AccessibilityDocument` is a complete read: the target and screen it was read against, each `AccessibilityDocumentElement` with its frame, attributes, interactability and coverage, the frontmost modal if one covers the target, a backend-specific `AccessibilityProfile` of timings, and, only when the read named a client, an `AccessibilityClientReport` saying which client, which tree it gets, and any caveat about reading it. `AccessibilityElementsResponse` carries a read with optional profiling data.
- **Rendering.** `AccessibilityOutputFormat` chooses between the complete document and the legacy element payload, which stays byte-stable for existing consumers. Traits arrive as a bitmask and are decoded to names with `AXExtractTraits`, through the `AXRuntime` private headers.

## Finding elements

An `AccessibilityElementQuery` names its element by a marker (a searchable key and value), by a point, or both. A tap can assert the value it expects to find before it acts, and every failure is a backend-neutral `UIAutomationError` that says whether retrying could help: a read that found nothing yet is worth polling, a broken reader is not. Polling and quiescence waits are built on that distinction.

How the readers behave, and the trade-offs between them, are described in [the accessibility documentation](https://www.fbidb.io/idb/accessibility).
