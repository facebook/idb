# FBSimulatorAX

Reads and drives the accessibility tree of an iOS Simulator's frontmost application, without a test bundle. It is the Simulator's accessibility capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not read accessibility does not link it.

It builds on [`FBAXCore`](../FBAXCore/README.md), whose requests and documents it reads into, and on `FBSimulatorControl`, whose display routing and guest bridge it reads through.

## Reading the tree

`Simulator.uiAutomation(backend:display:)` returns a `UIAutomation`: one query-shaped surface for element reads (`describe`, `wait`, `quiescence`) and element-targeted actions (`tap`, `scroll`, `setValue`, `drag`). The backend decides how the tree is read.

- **`.accessibility`** translates the frontmost application's tree on the host, through the private `AccessibilityPlatformTranslation` framework that `Simulator.app` uses. It reaches only the active display.
- **`.axBridge`** reads in the guest, at XCUITest fidelity, through the `SimulatorFrameworkBridge` helper that `FBSimulatorControl` runs inside the booted Simulator. Its persistence chooses which guest serves the read:
  - `.oneShot` spawns a guest per read. It holds nothing, so it costs nothing to reconstruct.
  - `.shared` reads over the Simulator's well-known socket, shared with every other process reading the same Simulator. The connection is released after each round trip so the next reader can have it, and only the guest's own idle timeout ends it.
  - `.exclusive` reads over a guest of the caller's own, on a socket nobody else can discover, and holds its connection between reads. The guest exits when that connection closes, so it suits a process that owns the Simulator for its lifetime.

Operations reach the display a `DisplaySelection` names and fail rather than reach another; see the multiple displays section of [the `FBSimulatorControl` README](../FBSimulatorControl/README.md).

## Finding elements

An `AccessibilityElementQuery` names its element by a marker (a searchable key and value), by a point, or both. A tap can assert the value it expects to find before it acts, and every failure is a backend-neutral `UIAutomationError` that says whether retrying could help: a read that found nothing yet is worth polling, a broken reader is not. Polling and quiescence waits are built on that distinction.

How the readers behave, and the trade-offs between them, are described in [the accessibility documentation](https://www.fbidb.io/idb/accessibility).
