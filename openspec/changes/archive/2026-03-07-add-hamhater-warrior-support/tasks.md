## 1. Target Registry

- [x] 1.1 Replace `TARGET_NAME` and `TRACKED_SPELLS` with a `TARGETS` table keyed by character name, each containing a `spells` sub-table mapping spell ID to spell name
- [x] 1.2 Add `activeTarget` and `activeSpells` variables (nil when no target detected)

## 2. Roster Scanning

- [x] 2.1 Implement `ScanRoster()` function that iterates raid/party unit IDs, matches against `TARGETS` keys, and returns the found target name or nil
- [x] 2.2 Implement `ApplyTarget(targetName)` function that sets `activeTarget`, `activeSpells`, updates button macrotext, button label text, and calls `Show()`/`SetButtonIdle()` — or `Hide()`/clears state if targetName is nil
- [x] 2.3 Register `GROUP_ROSTER_UPDATE` event and call `ScanRoster()` + `ApplyTarget()` from its handler

## 3. Deferred Combat Handling

- [x] 3.1 Add `pendingRescan` flag; set it when `GROUP_ROSTER_UPDATE` fires during `InCombatLockdown()`
- [x] 3.2 In `PLAYER_REGEN_ENABLED` handler, check `pendingRescan` and run `ScanRoster()` + `ApplyTarget()` if true

## 4. Combat Log and Alert Updates

- [x] 4.1 Update `COMBAT_LOG_EVENT_UNFILTERED` handler to check `destName` against `activeTarget` and `spellId` against `activeSpells` instead of the old hardcoded values
- [x] 4.2 Update `ShowAlert()` to use `activeTarget` for the alert message text

## 5. Initialization and Slash Commands

- [x] 5.1 Update `ADDON_LOADED` handler to run initial roster scan after position restore
- [x] 5.2 Update `PLAYER_LOGIN` message to display active target name and tracked spells, or "no target in group"
- [x] 5.3 Update `/bopnouar` status output and `/bopnouar test` to use active target context
