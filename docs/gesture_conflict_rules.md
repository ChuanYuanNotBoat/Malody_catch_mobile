# Gesture Conflict Rules

## Priority Order

1. Two-finger pinch zoom
2. Active box-select drag
3. Single-note drag (selected note hit)
4. Tap place/select
5. Long-press context menu

## Trigger Rules

- Pinch zoom:
  - requires 2 pointers
  - cancels single-finger drag candidate
- Box select:
  - starts on empty canvas drag
  - once active, move/select updates are owned by box select
- Note drag:
  - starts only when pointer down hits selected note
  - drag delta applies to current selection set
- Long-press:
  - uses framework long-press threshold
  - disabled while pinch/drag/box-select is active

## Mis-touch Regression Cases

- Drag selected note should not accidentally open context menu.
- Empty-area drag should start box select, not move nearest note.
- Two-finger gesture should always win over single-finger drag.
- Quick tap on note should select only once (no duplicate place).
