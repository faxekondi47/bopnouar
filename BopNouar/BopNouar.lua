local TARGET_NAME = "Twistedrogue"
local BOP_SPELL = "Blessing of Protection"
local ALERT_DURATION = 5

local TRACKED_SPELLS = {
    [13750] = "Adrenaline Rush",
    [13877] = "Blade Flurry",
}

-- Track which buffs are currently active (handles both expiring independently)
local activeBuffs = {}
local inCombat = false

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
-- Strategy: The button is always shown. We use SetAttribute("type", nil) to
-- make it non-functional when idle, and SetAttribute("type", "macro") when
-- active. A SecureHandlerStateTemplate manager ensures the type is set to
-- "macro" on combat entry (since SetAttribute is protected mid-combat).
-- Visual states (gray idle / green active with pulse) indicate clickability.
---------------------------------------------------------------------------
local bopButton = CreateFrame("Button", "BopNouarButton", UIParent, "SecureActionButtonTemplate")
bopButton:SetSize(220, 50)
bopButton:SetPoint("CENTER", 0, 140)
bopButton:SetFrameStrata("DIALOG")
bopButton:RegisterForClicks("AnyUp")
bopButton:SetAttribute("macrotext", "/cast [@" .. TARGET_NAME .. "] " .. BOP_SPELL)
bopButton:SetAttribute("type", nil)
bopButton:SetMovable(true)
bopButton:SetClampedToScreen(true)
bopButton:RegisterForDrag("LeftButton")

local bopBtnBg = bopButton:CreateTexture(nil, "BACKGROUND")
bopBtnBg:SetAllPoints()
bopBtnBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)

local bopBtnText = bopButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bopBtnText:SetPoint("CENTER")
bopBtnText:SetText("BoP " .. TARGET_NAME)
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
    pulseGroup:Play()
    bopButton:SetAlpha(1)
    if not InCombatLockdown() then
        bopButton:SetAttribute("type", "macro")
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
    else
        bopBtnBg:SetColorTexture(0.4, 0.4, 0.4, 0.7)
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if isButtonActive then
        GameTooltip:SetText("Click to BoP!", 0, 1, 0)
    else
        GameTooltip:SetText("Waiting for cooldowns...", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Shift+Drag to move", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)

bopButton:SetScript("OnLeave", function(self)
    if isButtonActive then
        bopBtnBg:SetColorTexture(0, 0.7, 0, 0.9)
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
alertText:SetPoint("CENTER", alertFrame, "CENTER", 0, 0)
alertText:SetTextColor(1, 1, 0, 1)

---------------------------------------------------------------------------
-- Auto-hide timer (alert frame only — button state is buff-driven)
---------------------------------------------------------------------------
local hideTimer = 0
local timerActive = false

frame:SetScript("OnUpdate", function(self, elapsed)
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
    alertText:SetText(TARGET_NAME .. " popped " .. spellName .. "!")
    alertFrame:Show()
    SetButtonActive()
    PlaySound(8959)
    hideTimer = ALERT_DURATION
    timerActive = true
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cFFFF0000[BopNouar]|r " .. TARGET_NAME .. " used " .. spellName .. "! BoP NOW!",
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
-- Event handling
---------------------------------------------------------------------------
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "BopNouar" then
            if not BopNouarDB then
                BopNouarDB = {}
            end
            RestorePosition()
            SetButtonIdle()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Loaded. Watching " .. TARGET_NAME ..
            " for Adrenaline Rush / Blade Flurry."
        )
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if next(activeBuffs) then
            SetButtonActive()
        else
            SetButtonIdle()
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent, _, _, _, _, _, _, destName, _, _, spellId =
            CombatLogGetCurrentEventInfo()

        -- Strip realm suffix for cross-realm compatibility ("Name-Realm" -> "Name")
        local nameOnly = destName and destName:match("^([^-]+)") or destName
        if nameOnly ~= TARGET_NAME then return end

        if TRACKED_SPELLS[spellId] then
            if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
                activeBuffs[spellId] = true
                ShowAlert(TRACKED_SPELLS[spellId])
            elseif subevent == "SPELL_AURA_REMOVED" then
                activeBuffs[spellId] = nil
                if not next(activeBuffs) then
                    if inCombat then
                        -- Can't set type=nil in combat; just go visually idle
                        isButtonActive = false
                        bopBtnBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)
                        bopBtnText:SetTextColor(0.5, 0.5, 0.5, 1)
                        pulseGroup:Stop()
                        alertFrame:Hide()
                        timerActive = false
                    else
                        SetButtonIdle()
                        alertFrame:Hide()
                        timerActive = false
                    end
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
        activeBuffs[13750] = true
        ShowAlert("Adrenaline Rush")
    elseif msg == "reset" then
        ResetPosition()
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Watching for " .. TARGET_NAME ..
            "'s Adrenaline Rush / Blade Flurry"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r /bopnouar test - Test the alert"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r /bopnouar reset - Reset button position"
        )
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cFF00FF00[BopNouar]|r Shift+Drag the button to move it"
        )
    end
end
