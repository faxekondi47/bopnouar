## Context

BopNouar is a single-file WoW TBC Classic addon (`BopNouar.lua`) that monitors "Twistedrogue" (Rogue) for offensive cooldowns and presents a BoP button. All target identity, spell tracking, and button labeling are hardcoded to a single player. The addon now needs to support a second character, "Hamhater" (Warrior), played by the same person on a different alt.

Key constraint: `SecureActionButtonTemplate` methods (`Show`, `Hide`, `SetAttribute`, `SetPoint`) are protected and cannot be called during combat lockdown.

## Goals / Non-Goals

**Goals:**
- Dynamically detect which of the two known characters is in the player's group/raid
- Configure the button (macrotext, label, tracked spells) for the detected target
- Hide the button when neither target is present; show it when one is found
- Track warrior cooldowns (Recklessness 1719, Death Wish 12292) alongside existing rogue cooldowns

**Non-Goals:**
- Supporting arbitrary/configurable target lists (UI for adding targets)
- Supporting more than one active target simultaneously (they're the same player)
- Creating multiple buttons

## Decisions

### Target registry as a table
Replace `TARGET_NAME` string and `TRACKED_SPELLS` table with a single `TARGETS` table keyed by character name, each entry containing its tracked spell IDs and spell names. This keeps the data co-located and makes adding future targets trivial.

```lua
local TARGETS = {
    ["Twistedrogue"] = {
        spells = { [13750] = "Adrenaline Rush", [13877] = "Blade Flurry" },
    },
    ["Hamhater"] = {
        spells = { [1719] = "Recklessness", [12292] = "Death Wish" },
    },
}
```

**Alternative**: Separate tables per target. Rejected — scatters related data and doesn't scale.

### Roster scanning for target detection
Register for `GROUP_ROSTER_UPDATE` to detect when group composition changes. Scan raid/party unit IDs to find a known target name. When found, set `activeTarget` and configure the button. When not found, clear `activeTarget` and hide the button.

Scan approach: iterate `"raid1"` through `"raidN"` if `IsInRaid()`, else `"party1"` through `"partyN"`. Use `UnitName()` to get each member's name.

Also run the scan on `ADDON_LOADED` / `PLAYER_LOGIN` to catch the case where the player is already in a group when logging in.

**Alternative**: Use `PARTY_MEMBERS_CHANGED` / `RAID_ROSTER_UPDATE` separately. Rejected — `GROUP_ROSTER_UPDATE` is the consolidated event available in TBC Classic 2.5.x.

### Deferred visibility changes during combat
If a roster change fires during `InCombatLockdown()`, set a `pendingRescan` flag. On `PLAYER_REGEN_ENABLED`, re-run the roster scan. This reuses the existing deferred-cleanup pattern (already used for `SetAttribute("type", nil)` on buff removal).

`Show()` and `Hide()` are both protected on `SecureActionButtonTemplate`, so there is no safe mid-combat alternative. The button simply stays in its current state until combat ends.

### First-match wins for target priority
If both character names are somehow detected in the group, the first one found during iteration wins. No explicit priority ordering needed — this scenario is effectively impossible since they're the same player's alts.

## Risks / Trade-offs

- **[Stale button state during combat]** If the target leaves the group mid-combat, the button remains visible until combat ends. Mitigation: deferred rescan on `PLAYER_REGEN_ENABLED`. This is a rare edge case and acceptable.
- **[GROUP_ROSTER_UPDATE availability]** If TBC Classic Anniversary doesn't fire `GROUP_ROSTER_UPDATE`, the scan won't trigger. Mitigation: the event is confirmed in TBC Classic 2.5.x clients. If issues arise, fallback to registering both `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE`.
