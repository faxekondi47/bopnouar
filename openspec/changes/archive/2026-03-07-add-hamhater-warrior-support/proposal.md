## Why

Anouar now plays a warrior alt ("Hamhater") in addition to "Twistedrogue" (Rogue). The addon needs to detect which character is in the group and dynamically target the correct one with the appropriate class-specific cooldown tracking, so the paladin can BoP whichever character Anouar is playing.

## What Changes

- Replace hardcoded single-target design with a multi-target configuration table mapping each character name to its tracked spell IDs
- Add group/raid roster scanning to detect which target is present and set the button's macrotext, label, and tracked spells accordingly
- Track warrior cooldowns: Recklessness (1719) and Death Wish (12292) for Hamhater
- Hide the button entirely when neither target is in the group/raid; show it when one is found
- Defer button Show/Hide to out-of-combat if roster changes occur during combat lockdown

## Capabilities

### New Capabilities
- `dynamic-target`: Group/raid roster scanning to detect which target is present, dynamic button configuration (macrotext, label, tracked spells), and button visibility tied to target presence

### Modified Capabilities

## Impact

- `BopNouar/BopNouar.lua`: All changes are in this single file. The hardcoded `TARGET_NAME` and `TRACKED_SPELLS` globals are replaced with a target registry and active-target resolution. Event registration adds group/raid roster events. Button text and macrotext update dynamically.
- `BopNouarDB` schema unchanged (position storage is target-agnostic)
- No new files or dependencies
