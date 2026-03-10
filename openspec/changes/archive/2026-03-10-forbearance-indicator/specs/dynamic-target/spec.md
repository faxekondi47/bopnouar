## MODIFIED Requirements

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
