.pragma library

var MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
              "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

function daysInMonth(year, month) {
  // Day 0 of the next month is the last day of this one.
  return new Date(year, month, 0).getDate()
}

// Always 42 cells. A fixed grid never reflows while paging months, which is
// what stops the arrows feeling jumpy.
function monthGrid(year, month) {
  var first = new Date(year, month - 1, 1)
  // getDay() is Sunday-first; the grid starts on Monday.
  var lead = (first.getDay() + 6) % 7
  var total = daysInMonth(year, month)
  var prev = daysInMonth(year, month - 1 === 0 ? 12 : month - 1)
  var cells = []
  for (var i = 0; i < lead; i++)
    cells.push({ day: prev - lead + 1 + i, month: -1 })
  for (var d = 1; d <= total; d++)
    cells.push({ day: d, month: 0 })
  var next = 1
  while (cells.length < 42)
    cells.push({ day: next++, month: 1 })
  return cells
}

function monthLabel(year, month) {
  return (MONTHS[month - 1] + " " + year).toUpperCase()
}

function shiftMonth(year, month, delta) {
  var index = (year * 12) + (month - 1) + delta
  return { year: Math.floor(index / 12), month: (index % 12) + 1 }
}

function isToday(cell, year, month, today) {
  if (!cell || cell.month !== 0 || !today) return false
  return today.getFullYear() === year
    && today.getMonth() + 1 === month
    && today.getDate() === cell.day
}
