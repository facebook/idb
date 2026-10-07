# FBAXCore

The accessibility data model: the requests a caller makes of a target's accessibility tree and the documents it gets back. Every reader produces this model, so a consumer can use one result regardless of which backend read it. The model also defines the wire vocabulary the in-guest `SimulatorFrameworkBridge` reader answers in.

It depends only on `FBControlCore`, and internal-imports the `AXRuntime` private headers for trait names. It holds no reader; the Simulator's readers are in `FBSimulatorControl`.

## What it provides

- **Requests.** `AccessibilityRequestOptions` gathers what a read asks for: which `AXKeys` to report, an `AccessibilityElementFilter` such as interactable-only, an `AccessibilityMatch` substring search, the traversal strategy (`AXTraversal`), whether to explain unreachable elements, and how to read remote content such as web views, which live in separate processes and need grid-based hit-testing.
- **Keys.** `AXKeys` names every attribute a read can report. Their raw values are the JSON keys on the wire and the cli's `--key` names, so they are stable. `AXSearchableKey` is the subset with string values that a search can match against.
- **Documents.** `AccessibilityDocument` is a complete read: the target and screen it was read against, each `AccessibilityDocumentElement` with its frame, attributes, interactability and coverage, the frontmost modal if one covers the target, and a backend-specific `AccessibilityProfile` of timings. `AccessibilityElementsResponse` carries a read with optional profiling data.
- **Rendering.** `AccessibilityOutputFormat` chooses between the complete document and the legacy element payload, which stays byte-stable for existing consumers. Traits arrive as a bitmask and are decoded to names with `AXExtractTraits`.

## Who reads it

Host-side translation and the in-guest bridge both answer with this model, which is why the bridge's request types in `FBSimulatorControl` encode with `AXTraversal` and `AXKeys`. How the Simulator reads its tree is described in [the accessibility documentation](https://www.fbidb.io/idb/accessibility).
