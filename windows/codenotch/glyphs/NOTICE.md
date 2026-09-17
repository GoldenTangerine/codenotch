<!--
@name: 供应商品牌图标许可
@Descripttion: 记录供应商图标来源与许可证。
@version: 1.0.0
@Author: sm
@Date: 2026-09-17 16:39:40
@LastEditTime: 2026-09-17 16:39:40
@FilePath: windows/codenotch/glyphs/NOTICE.md
-->
# Provider marks

The SVG files in this directory come from the npm package `@lobehub/icons-static-svg` 1.95.0
(https://github.com/lobehub/lobe-icons, MIT License). The artwork is unchanged;
local metadata comments may be added:

| File | Original file in the package | Shown in |
|---|---|---|
| claude.svg | icons/claude.svg | Claude cell |
| codex.svg | icons/openai.svg | Codex cell (the OpenAI mark, matching upstream Codenotch's glyph choice) |
| codex-alt.svg | icons/codex.svg | alternative: Codex's own mark |
| cursor.svg | icons/cursor.svg | Cursor cell |
| grok.svg | icons/grok.svg | Grok cell |
| gemini.svg | icons/antigravity.svg | Antigravity cell |
| gemini-alt.svg | icons/gemini.svg | alternative: the Gemini spark |

MIT License — Copyright (c) LobeHub. See that repository's LICENSE.

**Trademarks**: these marks are trademarks of Anthropic, OpenAI, Anysphere (Cursor), xAI (Grok) and Google
respectively, and are used here only to identify the product whose usage is displayed. Whether
they stay in a distributed build is the repository owner's call under each brand's guidelines;
they can be swapped for generated glyphs without touching any code.

**Overrides**: a file of the same name (`.svg` or `.png`) in `%APPDATA%\codenotch\glyphs\` takes
precedence over the built-in mark; it is picked up after "Refresh usage now" in the tray menu.
