# Changelog

## 0.4.0 – 2026-09-29
- Step 2: recipe sharing in the guild. Recipe IDs travel as small addon messages (prefix "CraftBoard",
  paced, at most 250 bytes); names, output and reagents are asked for once and cached. At login
  you send a fingerprint of your recipes and ask who else has CraftBoard; members whose data differs
  are fetched by whisper. Changes are broadcast a few seconds after you open a profession window.
  Data from other members is kept for offline members and cleared when you change guild.
- The window now shows "Synced ... ago" and how many members have shared. The refresh button asks the guild.
- `/cb share on|off`, `/cb sync`, `/cb selftest` (a fake guild member built from your own recipes) and
  `/cb selftest clear`.


## 0.3.1 – 2026-09-29
- "You share" dims professions whose window has not been opened yet and says which one to open.


## 0.3.0 – 2026-09-29
- The Allemano look: rounded corners and borders, orange accent (the Allemano mark), the new logo in
  the title bar and on the launcher, profession icons in the sidebar, search / whisper / mail / sync icons.
  Artwork sources moved to `Design/`, in-game media is `Media/Icons`, `Media/Logo`, `Media/ui`.


## 0.2.1 – 2026-09-29
- Fix: the window failed to open (a "." instead of ":" on the separator line).

## 0.2.0 – 2026-09-29
- Step 3: the CraftBoard window (`/cb` or the violet launcher button): professions on the left with
  an "online crafters only" filter and a "You share" panel, recipe search (name or reagent) and list
  in the middle, reagents and crafters (online first, Whisper / Mail) on the right. Shows your own
  characters now; guild members appear once recipe sharing (step 2) is added.
- Recipes with a cooldown are remembered as such, so "ready now" works when the cooldown is over.

## 0.1.0 – 2026-09-29
- Step 1: recipes for every character are saved automatically whenever a profession window is
  opened (learned recipes, output item, reagents, skill level, cooldown expiry). `/cb recipes` lists them.
- Guild profession list is saved at login; `/cb guildprof` tests whether expanding a profession
  header lists the members and their skill (players without CraftBoard).

## 0.0.2 – 2026-09-29
- First probe result: WoW Forever has no Classic trade skill API, only `C_TradeSkillUI`. Profession
  windows are now recorded through it (learned vs. unlearned recipes, the first six learned ones
  in full: output, reagents with item names and quantities, links, cooldown, craftable count).
- Probe of Blizzard's guild profession system: `IsGuildTradeSkillsEnabled`, the guild profession
  list, and one `QueryGuildMembersForRecipe` per session (who in the guild knows a recipe, even
  without CraftBoard).
- Fix: C_ results were saved as "<table>" instead of their fields; the missing chat message when a
  profession window opens.

## 0.0.1 – 2026-09-29

### Step 0 – Probe
- Addon skeleton: `CraftBoard.toc` (Interface 16001), namespace, event dispatcher, `CraftBoardDB`,
  error log (`/cb errors`, WoW Forever hides Lua errors), `/cb` and `/craftboard`.
- `/cb probe`: records which profession APIs exist (Classic trade skill + craft API, Retail
  `C_TradeSkillUI`), this character's professions, guild roster names, and sends addon messages of
  10–300 bytes to the guild and to yourself to find the size limit. Saved per character in
  `CraftBoardDB.probe` (read the SavedVariables file after /reload).
- Every time a profession window opens or updates, its recipes are recorded (all names, the first
  six in full: item and recipe links, reagents with counts and links, tools, cooldown).
- Event log: which profession, guild and addon message events fire, how often, last arguments.
- `/cb probe tooltip`: toggles a test line on item tooltips (checks whether CraftBoard can show
  "Craftable by" there later).
- Read-only: never crafts and never calls protected functions.
