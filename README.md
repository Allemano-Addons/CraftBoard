# CraftBoard

Who in your guild can craft what. Part of Allemano Addons, made for WoW Forever.

CraftBoard remembers the recipes of all your characters and shares them with the guild members who also
run the addon. Then you can search the whole guild's recipes, see who can make an item and whether they are
online, and whisper them with one click.

## Install

Unzip so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\CraftBoard`, then restart the
game (or `/reload`).

## How to use

1. **Open every profession window once** (once per character and profession). CraftBoard saves your recipes
   when the window opens. The "You share" box in the window shows which professions are still dimmed.
2. Open the window with `/cb` or the small button at the top of the screen.
3. Pick a profession on the left, search in the middle (recipe name or reagent), click a recipe to see the
   reagents and the crafters on the right. **Whisper** opens a chat with an online crafter, **Mail** fills in
   the mail address when a mailbox is open.
4. Reagents are real items: hover for the tooltip, shift-click to link, click to search the Auction House, and
   "Link all" puts every reagent with its count in the chat box.
5. Item tooltips show **Craftable by: ...** when someone in the guild can make the item.

The counts in the sidebar and the "N/M members" in the title bar grow as more guild members start using
CraftBoard. Members that are offline stay in the list with the recipes they last shared.

## What is sent to the guild

Recipe IDs, skill levels and cooldown timers, as small addon messages to guild members who run CraftBoard.
Nothing is sent outside your guild. You can turn sending off in the settings (you still receive).

## Commands

- `/cb` opens the window, `/cb settings` opens the settings.
- `/cb recipes` lists what is saved for your characters.
- `/cb sync` asks the guild for their recipes now.
- `/cb share on|off` turns sharing your recipes on or off.
- `/cb selftest` adds a fake guild member built from your own recipes, `/cb selftest clear` removes it.
- `/cb errors` shows the last Lua errors CraftBoard caught.

## Feedback

Screenshots and the output of `/cb errors` are the most useful things to send.
