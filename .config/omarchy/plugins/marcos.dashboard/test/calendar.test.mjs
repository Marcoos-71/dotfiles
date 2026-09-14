import { test } from "node:test"
import assert from "node:assert/strict"
import { loadQmlJs } from "./load.mjs"

const C = loadQmlJs(new URL("../Calendar.js", import.meta.url).pathname)

test("the grid is always six rows of seven", () => {
  assert.equal(C.monthGrid(2026, 9).length, 42)
  assert.equal(C.monthGrid(2026, 2).length, 42)
})

test("september 2026 starts on a tuesday, so monday is a filler day", () => {
  const grid = C.monthGrid(2026, 9)
  assert.deepEqual(grid[0], { day: 31, month: -1 })
  assert.deepEqual(grid[1], { day: 1, month: 0 })
})

test("a month starting on monday has no leading filler", () => {
  // June 2026 starts on a Monday.
  const grid = C.monthGrid(2026, 6)
  assert.deepEqual(grid[0], { day: 1, month: 0 })
})

test("a month starting on sunday pushes six filler days first", () => {
  // February 2026 starts on a Sunday.
  const grid = C.monthGrid(2026, 2)
  assert.equal(grid[6].day, 1)
  assert.equal(grid[6].month, 0)
  assert.equal(grid[0].month, -1)
})

test("leap february has twenty-nine days", () => {
  const days = C.monthGrid(2024, 2).filter(c => c.month === 0).map(c => c.day)
  assert.equal(days.length, 29)
  assert.equal(days[28], 29)
})

test("non-leap february has twenty-eight", () => {
  assert.equal(C.monthGrid(2026, 2).filter(c => c.month === 0).length, 28)
})

test("trailing cells belong to the next month", () => {
  const grid = C.monthGrid(2026, 9)
  assert.equal(grid[41].month, 1)
})

test("shiftMonth wraps forward across the year", () => {
  assert.deepEqual(C.shiftMonth(2026, 12, 1), { year: 2027, month: 1 })
})

test("shiftMonth wraps backward across the year", () => {
  assert.deepEqual(C.shiftMonth(2026, 1, -1), { year: 2025, month: 12 })
})

test("monthLabel is spanish and uppercase", () => {
  assert.equal(C.monthLabel(2026, 9), "SEPTIEMBRE 2026")
})

test("isToday only matches a current-month cell on the right date", () => {
  const today = new Date(2026, 8, 13)
  assert.equal(C.isToday({ day: 13, month: 0 }, 2026, 9, today), true)
  assert.equal(C.isToday({ day: 13, month: -1 }, 2026, 9, today), false)
  assert.equal(C.isToday({ day: 13, month: 0 }, 2026, 10, today), false)
})
