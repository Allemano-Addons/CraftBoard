# CraftBoard — media

Allemano mark: white triangle + orange chevron (`#F0763A`).

## Folders

- `Media/` goes into the addon: `CraftBoard/Media/...`
  - `Icons/*.tga`: 64×64, white on transparent. Tint them in Lua.
  - `Logo/cb_mark_{64,128,256}.tga`: two-color mark. `cb_mark_white_*`: all white. `cb_minimap.tga`: round minimap button.
- `PNG/`: CurseForge avatar (`logo/cb_curseforge_400.png`), mark up to 1024 px, icons at 256 px.
- `Source/`: SVG originals.

All TGA files are 32-bit with alpha and power-of-two sizes.

## Usage in Lua

```lua
local MEDIA = "Interface\\AddOns\\CraftBoard\\Media\\"
local ORANGE = { 0.941, 0.463, 0.227 } -- #F0763A

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(16, 16)
icon:SetTexture(MEDIA .. "Icons\\alchemy")  -- no file extension
icon:SetVertexColor(0.91, 0.91, 0.89)       -- inactive
-- icon:SetVertexColor(unpack(ORANGE))       -- active / selected
```

## Icons

UI: recipe, reagents, search, filter, sync, share, whisper, mail, cooldown, settings
Professions: alchemy, blacksmithing, enchanting, engineering, leatherworking, tailoring, cooking, first_aid
