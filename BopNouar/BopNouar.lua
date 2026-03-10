local BOP_SPELL = "Blessing of Protection"
local ALERT_DURATION = 5
local FORBEARANCE_SPELL_ID = 25771
local FORBEARANCE_DURATION = 60

local TARGETS = {
    ["Twistedrogue"] = {
        spells = { [13750] = "Adrenaline Rush", [13877] = "Blade Flurry" },
    },
    ["Hamhater"] = {
        spells = { [1719] = "Recklessness", [12292] = "Death Wish" },
    },
}

local activeTarget = nil
local activeSpells = nil

-- Track which buffs are currently active (handles both expiring independently)
local activeBuffs = {}
local inCombat = false
local pendingRescan = false
local hasForbearance = false
local forbearanceExpiry = 0

local DEFAULT_POSITION = { "CENTER", "CENTER", 0, 140 }

-- Main frame for event handling and timers
local frame = CreateFrame("Frame", "BopNouarFrame", UIParent)

---------------------------------------------------------------------------
-- BoP button (SecureActionButton)
--
-- IMPORTANT: On secure frames in TBC Classic, Show(), Hide(), EnableMouse(),
-- SetPoint(), and SetSize() are ALL protected and will cause "action blocked"
-- errors if called during combat. SetAlpha() is NOT protected.
--
-- Strategy: The button is hidden when no target is in group. When a target is
-- found, we Show() the button and configure its macrotext. We use
-- SetAttribute("type", nil) to make it non-functional when idle, and
-- SetAttribute("type", "macro") when active. A SecureHandlerStateTemplate
-- manager ensures the type is set to "macro" on combat entry.
-- Visual states (gray idle / green active with pulse) indicate clickability.
---------------------------------------------------------------------------
local bopButton = CreateFrame("Button", "BopNouarButton", UIParent, "SecureActionButtonTemplate")
bopButton:SetSize(220, 50)
bopButton:SetPoint("CENTER", 0, 140)
bopButton:SetFrameStrata("DIALOG")
bopButton:RegisterForClicks("AnyUp")
bopButton:SetAttribute("type", nil)
bopButton:SetMovable(true)
bopButton:SetClampedToScreen(true)
bopButton:RegisterForDrag("LeftButton")
bopButton:Hide()

local bopBtnBg = bopButton:CreateTexture(nil, "BACKGROUND")
bopBtnBg:SetAllPoints()
bopBtnBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)

local bopBtnText = bopButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bopBtnText:SetPoint("CENTER")
bopBtnText:SetText("BoP")
bopBtnText:SetTextColor(0.5, 0.5, 0.5, 1)

---------------------------------------------------------------------------
-- Pulse animation for active state
---------------------------------------------------------------------------
local pulseGroup = bopButton:CreateAnimationGroup()
pulseGroup:SetLooping("BOUNCE")
local pulse = pulseGroup:CreateAnimation("Alpha")
pulse:SetFromAlpha(1.0)
pulse:SetToAlpha(0.4)
pulse:SetDuration(0.6)
pulse:SetSmoothing("IN_OUT")

---------------------------------------------------------------------------
-- Secure manager frame — toggles type="macro" on combat entry
---------------------------------------------------------------------------
local secureManager = CreateFrame("Frame", "BopNouarSecureManager", UIParent,
    "SecureHandlerStateTemplate")
secureManager:SetFrameRef("bopButton", bopButton)
RegisterStateDriver(secureManager, "combat", "[combat] incombat; ooc")
secureManager:SetAttribute("_onstate-combat", [[
    local btn = self:GetFrameRef("bopButton")
    if newstate == "incombat" then
        btn:SetAttribute("type", "macro")
    end
]])

---------------------------------------------------------------------------
-- Button state functions
---------------------------------------------------------------------------
local isButtonActive = false

local function SetButtonIdle()
    isButtonActive = false
    bopBtnBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    bopBtnText:SetTextColor(0.5, 0.5, 0.5, 1)
    if activeTarget then
        bopBtnText:SetText("BoP " .. activeTarget)
    end
    pulseGroup:Stop()
    bopButton:SetAlpha(1)
    if not InCombatLockdown() then
        bopButton:SetAttribute("type", nil)
    end
end

local function SetButtonActive()
    isButtonActive = true
    bopBtnBg:SetColorTexture(0, 0.7, 0, 0.9)
    bopBtnText:SetTextColor(1, 1, 1, 1)
    if activeTarget then
        bopBtnText:SetText("BoP " .. activeTarget)
    end
    pulseGroup:Play()
    bopButton:SetAlpha(1)
    if not InCombatLockdown() then
        bopButton:SetAttribute("type", "macro")
    end
end

local function SetButtonBlocked()
    isButtonActive = false
    bopBtnBg:SetColorTexture(0.9, 0.5, 0, 0.9)
    bopBtnText:SetTextColor(1, 1, 1, 1)
    pulseGroup:Stop()
    bopButton:SetAlpha(1)
    local remaining = forbearanceExpiry - GetTime()
    if remaining < 0 then remaining = 0 end
    local m = math.floor(remaining / 60)
    local s = math.floor(remaining % 60)
    bopBtnText:SetText(string.format("Forbearance %d:%02d", m, s))
    if not InCombatLockdown() then
        bopButton:SetAttribute("type", nil)
    end
end

---------------------------------------------------------------------------
-- State resolution
---------------------------------------------------------------------------
local function ResolveButtonState()
    if not activeTarget then return end
    if next(activeBuffs) then
        if hasForbearance then
            SetButtonBlocked()
        else
            SetButtonActive()
        end
    else
        SetButtonIdle()
    end
end

---------------------------------------------------------------------------
-- Roster scanning and target application
---------------------------------------------------------------------------
local function ScanRoster()
    if IsInRaid() then
        for i = 1, MAX_RAID_MEMBERS do
            local name = UnitName("raid" .. i)
            if name and TARGETS[name] then
                return name
            end
        end
    else
        for i = 1, MAX_PARTY_MEMBERS do
            local name = UnitName("party" .. i)
            if name and TARGETS[name] then
                return name
            end
        end
    end
    return nil
end

local function ApplyTarget(targetName)
    if targetName == activeTarget then return end

    -- Clear stale buff and Forbearance tracking on target change
    activeBuffs = {}
    hasForbearance = false
    forbearanceExpiry = 0

    if targetName then
        activeTarget = targetName
        activeSpells = TARGETS[targetName].spells
        bopBtnText:SetText("BoP " .. targetName)
        if not InCombatLockdown() then
            bopButton:SetAttribute("macrotext", "/cast [@" .. targetName .. "] " .. BOP_SPELL)
            bopButton:Show()
        end
        ResolveButtonState()
    else
        activeTarget = nil
        activeSpells = nil
        if not InCombatLockdown() then
            bopButton:SetAttribute("type", nil)
            bopButton:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Shift+drag handlers
---------------------------------------------------------------------------
bopButton:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then
        self:StartMoving()
    end
end)

bopButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    if BopNouarDB then
        BopNouarDB.position = { point, relativePoint, x, y }
    end
end)

---------------------------------------------------------------------------
-- Tooltip / hover
---------------------------------------------------------------------------
bopButton:SetScript("OnEnter", function(self)
    if isButtonActive then
        bopBtnBg:SetColorTexture(0, 0.85, 0, 1)
    elseif hasForbearance and next(activeBuffs) then
        bopBtnBg:SetColorTexture(1, 0.6, 0.1, 1)
    else
        bopBtnBg:SetColorTexture(0.4, 0.4, 0.4, 0.7)
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if isButtonActive then
        GameTooltip:SetText("Click to BoP!", 0, 1, 0)
    elseif hasForbearance and next(activeBuffs) then
        GameTooltip:SetText("Forbearance active — wait for it to expire", 1, 0.5, 0)
    else
        GameTooltip:SetText("Waiting for cooldowns...", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Shift+Drag to move", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)

bopButton:SetScript("OnLeave", function(self)
    if isButtonActive then
        bopBtnBg:SetColorTexture(0, 0.7, 0, 0.9)
    elseif hasForbearance and next(activeBuffs) then
        bopBtnBg:SetColorTexture(0.9, 0.5, 0, 0.9)
    else
        bopBtnBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    end
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Alert frame (non-secure, pure visual - safe to Show/Hide in combat)
---------------------------------------------------------------------------
local alertFrame = CreateFrame("Frame", "BopNouarAlert", UIParent)
alertFrame:SetSize(400, 50)
alertFrame:SetPoint("BOTTOM", bopButton, "TOP", 0, 10)
alertFrame:SetFrameStrata("DIALOG")
alertFrame:Hide()

local alertBg = alertFrame:CreateTexture(nil, "BACKGROUND")
alertBg:SetAllPoints()
alertBg:SetColorTexture(0.8, 0, 0, 0.7)

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
alertText:SetPoint("CENTER", alertFrame, "CENTER", 0, 8)
alertText:SetTextColor(1, 1, 0, 1)

local alertForbText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
alertForbText:SetPoint("TOP", alertText, "BOTTOM", 0, -2)
alertForbText:SetTextColor(1, 0.5, 0, 1)
alertForbText:Hide()

---------------------------------------------------------------------------
-- Auto-hide timer (alert frame only — button state is buff-driven)
---------------------------------------------------------------------------
local hideTimer = 0
local timerActive = false

frame:SetScript("OnUpdate", function(self, elapsed)
    if hasForbearance then
        local remaining = forbearanceExpiry - GetTime()
        if remaining <= 0 then
            hasForbearance = false
            forbearanceExpiry = 0
            ResolveButtonState()
            if alertFrame:IsShown() and alertForbText then
                alertForbText:Hide()
            end
        else
            local m = math.floor(remaining / 60)
            local s = math.floor(remaining % 60)
            local timeStr = string.format("%d:%02d", m, s)
            if next(activeBuffs) then
                bopBtnText:SetText("Forbearance " .. timeStr)
            end
            if alertFrame:IsShown() and alertForbText then
                alertForbText:SetText("Forbearance active! (" .. timeStr .. ")")
            end
        end
    end

    if not timerActive then return end
    hideTimer = hideTimer - elapsed
    if hideTimer <= 0 then
        timerActive = false
        alertFrame:Hide()
    end
end)

---------------------------------------------------------------------------
-- Alert functions
---------------------------------------------------------------------------
local function ShowAlert(spellName)
    alertText:SetText(activeTarget .. " popped " .. spellName .. "!")
    if hasForbearance then
        local remaining = forbearanceExpiry - GetTime()
        if remaining < 0 then remaining = 0 end
        local m = math.floor(remaining / 60)
        local s = math.floor(remaining % 60)
        alertForbText:SetText(string.format("Forbearance active! (%d:%02d)", m, s))
        alertForbText:Show()
    else
        alertForbText:Hide()
    end
    alertFrame:Show()
    ResolveButtonState()
    PlaySound(8959)
    hideTimer = ALERT_DURATION
    timerActive = true
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cFFFF0000[BopNouar]|r " .. activeTarget .. " used " .. spellName .. "! BoP NOW!",
        1, 1, 0
    )
end

-- Dismiss alert on click (button visual stays active until buffs actually fade)
bopButton:HookScript("OnClick", function()
    alertFrame:Hide()
    timerActive = false
end)

---------------------------------------------------------------------------
-- Position helpers
---------------------------------------------------------------------------
local function RestorePosition()
    if BopNouarDB and BopNouarDB.position then
        local pos = BopNouarDB.position
        bopButton:ClearAllPoints()
        bopButton:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
end

local function ResetPosition()
    if InCombatLockdown() then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFFFF0000[BopNouar]|r Cannot reset position during combat."
        )
        return
    end
    bopButton:ClearAllPoints()
    bopButton:SetPoint(DEFAULT_POSITION[1], UIParent, DEFAULT_POSITION[2],
        DEFAULT_POSITION[3], DEFAULT_POSITION[4])
    if BopNouarDB then
        BopNouarDB.position = nil
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[BopNouar]|r Button position reset.")
end

---------------------------------------------------------------------------
-- Spell list helper
---------------------------------------------------------------------------
local function GetSpellNames(spells)
    local names = {}
    for _, name in pairs(spells) do
        names[#names + 1] = name
    end
    return table.concat(names, " / ")
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BopNouar" then
            if not BopNouarDB then
                BopNouarDB = {}
            end
            RestorePosition()
            ApplyTarget(ScanRoster())
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if activeTarget then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF00FF00[BopNouar]|r Loaded. Watching " .. activeTarget ..
                " for " .. GetSpellNames(activeSpells) .. "."
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF00FF00[BopNouar]|r Loaded. No tracked target in group."
            )
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if InCombatLockdown() then
            pendingRescan = true
        else
            ApplyTarget(ScanRoster())
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if pendingRescan then
            pendingRescan = false
            ApplyTarget(ScanRoster())
        end
        if activeTarget then
            ResolveButtonState()
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not activeTarget then return end

        local _, subevent, _, _, _, _, _, _, destName, _, _, spellId =
            CombatLogGetCurrentEventInfo()

        -- Strip realm suffix for cross-realm compatibility ("Name-Realm" -> "Name")
        local nameOnly = destName and destName:match("^([^-]+)") or destName
        if nameOnly ~= activeTarget then return end

        if spellId == FORBEARANCE_SPELL_ID then
            if subevent == "SPELL_AURA_APPLIED" then
                hasForbearance = true
                forbearanceExpiry = GetTime() + FORBEARANCE_DURATION
                ResolveButtonState()
            elseif subevent == "SPELL_AURA_REMOVED" then
                hasForbearance = false
                forbearanceExpiry = 0
                ResolveButtonState()
            end
        elseif activeSpells[spellId] then
            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                activeBuffs[spellId] = true
                ShowAlert(activeSpells[spellId])
            elseif subevent == "SPELL_AURA_REMOVED" then
                activeBuffs[spellId] = nil
                if not next(activeBuffs) then
                    ResolveButtonState()
                    alertFrame:Hide()
                    timerActive = false
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_BOPNOUAR1 = "/bopnouar"
SlashCmdList["BOPNOUAR"] = function(msg)
    msg = msg and msg:trim():lower() or ""
    if msg == "test" then
        if activeTarget then
            local spellId, spellName = next(activeSpells)
            activeBuffs[spellId] = true
            ShowAlert(spellName)
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFFF0000[BopNouar]|r No tracked target in group. Cannot test."
            )
        end
    elseif msg == "test forbearance" then
        if activeTarget then
            local spellId, spellName = next(activeSpells)
            activeBuffs[spellId] = true
            hasForbearance = true
            forbearanceExpiry = GetTime() + FORBEARANCE_DURATION
            ShowAlert(spellName)
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFFFF0000[BopNouar]|r No tracked target in group. Cannot test."
            )
        end
    elseif msg == "reset" then
        ResetPosition()
    else
        if activeTarget then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF00FF00[BopNouar]|r Watching " .. activeTarget ..
                " for " .. GetSpellNames(activeSpells)
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cFF00FF00[BopNouar]|r No tracked target in group."
            )
        end
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r /bopnouar test - Test the alert"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r /bopnouar test forbearance - Test alert with Forbearance"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r /bopnouar reset - Reset button position"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Shift+Drag the button to move it"
        )
    end
end
