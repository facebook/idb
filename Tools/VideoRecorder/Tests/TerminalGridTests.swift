/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SimulatorVideo
import Testing

@Suite struct TerminalGridTests {
  @Test func portraitSurfaceFitsTerminalHeight() {
    let grid = TerminalGrid.fitting(surfaceWidth: 1206, surfaceHeight: 2622, terminalColumns: 80, terminalRows: 24)
    #expect(grid == TerminalGrid(columns: 22, rows: 24))
  }

  @Test func landscapeSurfaceFitsTerminalWidth() {
    let grid = TerminalGrid.fitting(surfaceWidth: 2622, surfaceHeight: 1206, terminalColumns: 80, terminalRows: 24)
    #expect(grid == TerminalGrid(columns: 80, rows: 18))
  }

  @Test func neverCollapsesBelowOneCell() {
    let grid = TerminalGrid.fitting(surfaceWidth: 10_000, surfaceHeight: 1, terminalColumns: 4, terminalRows: 4)
    #expect(grid == TerminalGrid(columns: 4, rows: 1))
  }

  @Test func emptySurfaceFillsTerminal() {
    let grid = TerminalGrid.fitting(surfaceWidth: 0, surfaceHeight: 0, terminalColumns: 80, terminalRows: 24)
    #expect(grid == TerminalGrid(columns: 80, rows: 24))
  }
}
