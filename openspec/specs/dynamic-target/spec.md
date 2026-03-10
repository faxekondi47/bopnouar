## ADDED Requirements

### Requirement: Target registry with class-specific spells
The addon SHALL maintain a target registry mapping character names to their tracked spell IDs:
- "Twistedrogue": Adrenaline Rush (13750), Blade Flurry (13877)
- "Hamhater": Recklessness (1719), Death Wish (12292)

#### Scenario: Rogue target detected
- **WHEN** "Twistedrogue" is found in the group/raid
- **THEN** the addon SHALL track spell IDs 13750 and 13877 in the combat log

#### Scenario: Warrior target detected
- **WHEN** "Hamhater" is found in the group/raid
- **THEN** the addon SHALL track spell IDs 1719 and 12292 in the combat log

### Requirement: Roster scanning for active target
The addon SHALL scan the group/raid roster on `GROUP_ROSTER_UPDATE` to determine which known target is present. The addon SHALL also scan on `ADDON_LOADED` to handle being already grouped at login. When the active target changes, Forbearance tracking state (`hasForbearance`, `forbearanceExpiry`) SHALL be cleared alongside `activeBuffs`.

#### Scenario: Target joins group
- **WHEN** a `GROUP_ROSTER_UPDATE` fires and a known target name is found among raid or party unit names
- **THEN** `activeTarget` SHALL be set to that target's name, the button SHALL be configured with that target's macrotext and tracked spells, and Forbearance state SHALL be cleared

#### Scenario: No target in group
- **WHEN** a `GROUP_ROSTER_UPDATE` fires and no known target name is found in the group/raid
- **THEN** `activeTarget` SHALL be cleared to nil, the button SHALL be hidden, and Forbearance state SHALL be cleared

#### Scenario: Solo player
- **WHEN** the player is not in any group or raid
- **THEN** `activeTarget` SHALL be nil, the button SHALL be hidden, and Forbearance state SHALL be cleared

### Requirement: Dynamic button configuration
When an active target is detected, the button SHALL update its macrotext to `/cast [@<targetName>] Blessing of Protection`, its label text to `"BoP <targetName>"`, and become visible.

#### Scenario: Button configured for Twistedrogue
- **WHEN** activeTarget is set to "Twistedrogue"
- **THEN** the button macrotext SHALL be `/cast [@Twistedrogue] Blessing of Protection` and the label SHALL read "BoP Twistedrogue"

#### Scenario: Button configured for Hamhater
- **WHEN** activeTarget is set to "Hamhater"
- **THEN** the button macrotext SHALL be `/cast [@Hamhater] Blessing of Protection` and the label SHALL read "BoP Hamhater"

### Requirement: Button visibility tied to target presence
The button SHALL be shown only when an active target is present in the group/raid. When no target is present, the button SHALL be hidden and non-clickable (`type` set to nil).

#### Scenario: Target present
- **WHEN** activeTarget is not nil and the player is not in combat lockdown
- **THEN** the button SHALL be shown via `Show()` and set to idle visual state

#### Scenario: Target absent
- **WHEN** activeTarget is nil and the player is not in combat lockdown
- **THEN** the button SHALL be hidden via `Hide()` and its type attribute SHALL be nil

### Requirement: Deferred visibility during combat
If a roster change occurs during combat lockdown, the addon SHALL defer the roster rescan and any resulting `Show()`/`Hide()` calls until `PLAYER_REGEN_ENABLED`.

#### Scenario: Roster change during combat
- **WHEN** `GROUP_ROSTER_UPDATE` fires while `InCombatLockdown()` is true
- **THEN** the addon SHALL set a `pendingRescan` flag and NOT call `Show()`, `Hide()`, or `SetAttribute()` until combat ends

#### Scenario: Combat ends with pending rescan
- **WHEN** `PLAYER_REGEN_ENABLED` fires and `pendingRescan` is true
- **THEN** the addon SHALL run the roster scan and apply any visibility or configuration changes

### Requirement: Combat log filtering by active target
The combat log scanner SHALL only process events for the current `activeTarget` and only for that target's associated spell IDs.

#### Scenario: Event for active target's tracked spell
- **WHEN** a `SPELL_AURA_APPLIED` fires for activeTarget with a spell ID in the target's spell list
- **THEN** the addon SHALL trigger the alert and activate the button

#### Scenario: Event for non-active target
- **WHEN** a combat log event fires for a character name that is not the activeTarget
- **THEN** the addon SHALL ignore the event

### Requirement: Login message reflects active target
The login status message SHALL display which target is being watched, or indicate that no target is in the group.

#### Scenario: Target present at login
- **WHEN** the player logs in and a known target is in the group
- **THEN** the status message SHALL include the target's name and their tracked cooldown names

#### Scenario: No target at login
- **WHEN** the player logs in and no known target is in the group
- **THEN** the status message SHALL indicate that no tracked target is in the group
