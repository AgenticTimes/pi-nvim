# User bubble box (border + background)

> Styling superseded by `2026-09-20-three-role-boxes-design.md` (user turn is now a
> rounded blue box, tool and thinking got their own distinct boxes).

## Goal

User turns look like a boxed bubble: blue left bar `▌`, unicode border, light background. Assistant/thinking unchanged.

## Approach

- Paint via extmarks only (no border chars in buffer text).
- `append_user` records line range, then `paint_user_bubble`.
- Highlights: `PiYouBubble` (bg), `PiYouBorder` (box), existing `PiYouBar`.
- Repaint on `WinResized` so border width tracks the chat window.
- `[[`/`]]` still key off `PiYouBar` / `▌` on the first content line.

## Out of scope

Assistant framing, thinking chrome, writing box chars into yankable text.
