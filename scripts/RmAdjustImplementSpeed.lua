--[[
    RmAdjustImplementSpeed.lua

    Vehicle specialization for dynamic working speed adjustment.
    - RShift+1/2: Increase/decrease implement working speed limits
    - RShift+0: Toggle "antigravity" (bypass PowerConsumer speed offsets and drag force)

    Registered dynamically into all vehicle types.
    Speed adjustments are non-persistent (reset on map reload).

    NOTE: This file is sourced by g_specializationManager:addSpecialization(),
    NOT directly by main.lua. Registration and injection are handled in main.lua.

    Author: Ritter
    Version: 1.0.0.0
]]

-- Per-mod logger instance with automatic multiplayer context
local Log = RmLogging.getLogger("AdjustImplementSpeed")

-- Module declaration
RmAdjustImplementSpeed = {}

-- Module constants
RmAdjustImplementSpeed.SPEED_STEP = 1               -- km/h per key press
RmAdjustImplementSpeed.SPEED_FLOOR = 1              -- minimum speed limit in km/h
RmAdjustImplementSpeed.NOTIFICATION_DURATION = 2000  -- notification display time in ms

-- Spec table name on vehicle: "spec_modName.specShortName"
RmAdjustImplementSpeed.SPEC_TABLE_NAME = ("spec_%s.rmAdjustImplementSpeed"):format(g_currentModName)

-- ============================================================================
-- SPECIALIZATION INTERFACE
-- ============================================================================

---Check if prerequisites are met.
---Returns true for all vehicle types -- we need getRawSpeedLimit override on implements too.
---@param specializations table List of specializations
---@return boolean
function RmAdjustImplementSpeed.prerequisitesPresent(specializations)
    return true
end

---Register specialization functions on the vehicle type
---@param vehicleType table
function RmAdjustImplementSpeed.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "aisGetSpeedLimitedImplements", RmAdjustImplementSpeed.aisGetSpeedLimitedImplements)
    SpecializationUtil.registerFunction(vehicleType, "aisAdjustSpeed", RmAdjustImplementSpeed.aisAdjustSpeed)
    SpecializationUtil.registerFunction(vehicleType, "aisGetEffectiveSpeedLimit", RmAdjustImplementSpeed.aisGetEffectiveSpeedLimit)
    SpecializationUtil.registerFunction(vehicleType, "aisIsAntigravityEnabled", RmAdjustImplementSpeed.aisIsAntigravityEnabled)
    SpecializationUtil.registerFunction(vehicleType, "aisSetAntigravity", RmAdjustImplementSpeed.aisSetAntigravity)
end

---Register overwritten functions
---@param vehicleType table
function RmAdjustImplementSpeed.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getRawSpeedLimit", RmAdjustImplementSpeed.getRawSpeedLimit)
end

---Register event listeners
---@param vehicleType table
function RmAdjustImplementSpeed.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RmAdjustImplementSpeed)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", RmAdjustImplementSpeed)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", RmAdjustImplementSpeed)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", RmAdjustImplementSpeed)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

---Called when vehicle loads
---@param savegame table|nil
function RmAdjustImplementSpeed:onLoad(savegame)
    Log:trace(">>> onLoad() vehicle=%s", self.configFileName or "unknown")
    local spec = self[RmAdjustImplementSpeed.SPEC_TABLE_NAME]
    if spec == nil then
        Log:debug("SKIP: spec table not found in onLoad")
        return
    end
    spec.actionEvents = {}
end

---Called when vehicle is deleted/destroyed
function RmAdjustImplementSpeed:onDelete()
    Log:trace(">>> onDelete() vehicle=%s", self.configFileName or "unknown")
    -- Restore friction force if antigravity was enabled
    if self._aisAntigravity and self._aisOrigMaxForce ~= nil then
        local pcSpec = self.spec_powerConsumer
        if pcSpec ~= nil then
            pcSpec.maxForce = self._aisOrigMaxForce
        end
    end
    self._aisSpeedDelta = nil
    self._aisAntigravity = nil
    self._aisOrigMaxForce = nil
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

---Register action events when player enters vehicle.
---Keybindings only appear when the vehicle has implements with finite speed limits.
---Uses getIsActiveForInput(true, true) to keep keybinds active during AI operation,
---following the same pattern as Drivable.lua for cruise control adjustment.
---@param isActiveForInput boolean
---@param isActiveForInputIgnoreSelection boolean
function RmAdjustImplementSpeed:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self[RmAdjustImplementSpeed.SPEC_TABLE_NAME]
    if spec == nil then
        Log:debug("SKIP: spec table nil in onRegisterActionEvents")
        return
    end
    self:clearActionEventsTable(spec.actionEvents)

    -- Use activeForAI=true so keybinds remain registered during AI worker operation.
    -- The passed isActiveForInputIgnoreSelection is false when AI is active.
    if not self:getIsActiveForInput(true, true) then
        return
    end

    Log:trace(">>> onRegisterActionEvents() vehicle=%s aiActive=%s",
        tostring(self.configFileName), tostring(self:getIsAIActive()))

    -- Only register keybindings if vehicle has implements with finite speed limits
    local implements = self:aisGetSpeedLimitedImplements()
    if #implements == 0 then
        Log:trace("<<< onRegisterActionEvents: no speed-limited implements")
        return
    end

    Log:debug("KEYBINDS: registering for %d speed-limited implements", #implements)

    -- Speed up action
    local _, actionEventId = self:addActionEvent(
        spec.actionEvents,
        InputAction.ADJUST_IMPLEMENT_SPEED_UP,
        self,
        RmAdjustImplementSpeed.onSpeedUp,
        false, -- triggerUp
        true,  -- triggerDown
        false, -- triggerAlways
        true   -- startActive
    )
    if actionEventId ~= nil then
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_aisSpeedUp"))
    end

    -- Speed down action
    _, actionEventId = self:addActionEvent(
        spec.actionEvents,
        InputAction.ADJUST_IMPLEMENT_SPEED_DOWN,
        self,
        RmAdjustImplementSpeed.onSpeedDown,
        false, -- triggerUp
        true,  -- triggerDown
        false, -- triggerAlways
        true   -- startActive
    )
    if actionEventId ~= nil then
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_aisSpeedDown"))
    end

    -- Antigravity toggle action
    local antigravityEnabled = self:aisIsAntigravityEnabled()
    local antigravityText = antigravityEnabled
        and g_i18n:getText("action_aisAntigravityDisable")
        or g_i18n:getText("action_aisAntigravityEnable")

    _, actionEventId = self:addActionEvent(
        spec.actionEvents,
        InputAction.ADJUST_IMPLEMENT_SPEED_ANTIGRAVITY,
        self,
        RmAdjustImplementSpeed.onAntigravityToggle,
        false, -- triggerUp
        true,  -- triggerDown
        false, -- triggerAlways
        true   -- startActive
    )
    if actionEventId ~= nil then
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_NORMAL)
        g_inputBinding:setActionEventText(actionEventId, antigravityText)
        spec.antigravityActionEventId = actionEventId
    end
end

---Callback for speed up action
---@param actionName string
---@param inputValue number
---@param callbackState any
---@param isAnalog boolean
function RmAdjustImplementSpeed:onSpeedUp(actionName, inputValue, callbackState, isAnalog)
    self:aisAdjustSpeed(RmAdjustImplementSpeed.SPEED_STEP)
end

---Callback for speed down action
---@param actionName string
---@param inputValue number
---@param callbackState any
---@param isAnalog boolean
function RmAdjustImplementSpeed:onSpeedDown(actionName, inputValue, callbackState, isAnalog)
    self:aisAdjustSpeed(-RmAdjustImplementSpeed.SPEED_STEP)
end

---Callback for antigravity toggle action
---@param actionName string
---@param inputValue number
---@param callbackState any
---@param isAnalog boolean
function RmAdjustImplementSpeed:onAntigravityToggle(actionName, inputValue, callbackState, isAnalog)
    local currentlyEnabled = self:aisIsAntigravityEnabled()
    self:aisSetAntigravity(not currentlyEnabled)
end

-- ============================================================================
-- HUD STATUS LINE
-- ============================================================================

---Draw status line in F1 help panel showing current working speed and antigravity state.
---@param dt number Delta time in ms
function RmAdjustImplementSpeed:onDraw(dt)
    if not self.isClient or self ~= self.rootVehicle then
        return
    end
    if not self:getIsActiveForInput(true, true) then
        return
    end
    local speed = self:aisGetEffectiveSpeedLimit()
    if speed == nil then
        return
    end
    local text = string.format(g_i18n:getText("ais_statusLine"), speed)
    if self:aisIsAntigravityEnabled() then
        text = text .. " | AG"
    end
    g_currentMission:addExtraPrintText(text)
end

-- ============================================================================
-- IMPLEMENT DETECTION
-- ============================================================================

---Collect all attached implements (recursive) that have a finite speed limit.
---@return table Array of vehicle objects with finite speedLimit
function RmAdjustImplementSpeed:aisGetSpeedLimitedImplements()
    Log:trace(">>> aisGetSpeedLimitedImplements()")
    local result = {}

    -- Collect from attached implements only.
    -- The root vehicle (tractor) is excluded -- only attached tools are adjustable.
    -- TODO: For self-propelled harvesters driven directly, consider adding self-detection.
    RmAdjustImplementSpeed.collectImplementsRecursive(self, result)

    Log:trace("<<< aisGetSpeedLimitedImplements = %d", #result)
    return result
end

---Recursively collect implements with finite speed limits
---@param vehicle table Vehicle to search from
---@param result table Array to append found implements to
function RmAdjustImplementSpeed.collectImplementsRecursive(vehicle, result)
    if vehicle.getAttachedImplements == nil then
        return
    end

    local attachedImplements = vehicle:getAttachedImplements()
    if attachedImplements == nil then
        return
    end

    for _, implement in ipairs(attachedImplements) do
        if implement.object ~= nil then
            local obj = implement.object
            if obj.speedLimit ~= nil and obj.speedLimit ~= math.huge then
                table.insert(result, obj)
            end
            RmAdjustImplementSpeed.collectImplementsRecursive(obj, result)
        end
    end
end

-- ============================================================================
-- SPEED ADJUSTMENT
-- ============================================================================

---Adjust speed for all attached speed-limited implements.
---Applies a delta to the stored _aisSpeedDelta on each implement.
---Shows a side notification with the new effective speed.
---@param delta number Speed change in km/h (positive = faster, negative = slower)
function RmAdjustImplementSpeed:aisAdjustSpeed(delta)
    Log:trace(">>> aisAdjustSpeed(delta=%d)", delta)

    local implements = self:aisGetSpeedLimitedImplements()
    if #implements == 0 then
        Log:debug("ADJUST: no speed-limited implements")
        return
    end

    for _, impl in ipairs(implements) do
        local currentDelta = impl._aisSpeedDelta or 0
        local newDelta = currentDelta + delta

        -- impl.speedLimit is the original XML value (never modified by us).
        -- getRawSpeedLimit() adds _aisSpeedDelta at query time.
        local adjustedSpeed = impl.speedLimit + newDelta
        if adjustedSpeed < RmAdjustImplementSpeed.SPEED_FLOOR then
            newDelta = RmAdjustImplementSpeed.SPEED_FLOOR - impl.speedLimit
        end

        impl._aisSpeedDelta = newDelta
        Log:debug("ADJUST: %s delta=%d base=%d effective=%d",
            impl.configFileName or "unknown", newDelta, impl.speedLimit, impl.speedLimit + newDelta)
    end
end

---Get the effective (minimum) speed limit across all adjusted implements.
---@return number|nil effectiveSpeed The minimum adjusted speed, or nil if no implements
function RmAdjustImplementSpeed:aisGetEffectiveSpeedLimit()
    local implements = self:aisGetSpeedLimitedImplements()
    if #implements == 0 then
        return nil
    end

    local minSpeed = math.huge
    for _, impl in ipairs(implements) do
        local delta = impl._aisSpeedDelta or 0
        local adjustedSpeed = impl.speedLimit + delta
        minSpeed = math.min(minSpeed, adjustedSpeed)
    end

    if minSpeed == math.huge then
        return nil
    end
    return math.max(math.floor(minSpeed), RmAdjustImplementSpeed.SPEED_FLOOR)
end

-- ============================================================================
-- ANTIGRAVITY
-- ============================================================================

---Check if antigravity is currently enabled on any attached implement.
---@return boolean enabled True if antigravity is active
function RmAdjustImplementSpeed:aisIsAntigravityEnabled()
    local implements = self:aisGetSpeedLimitedImplements()
    for _, impl in ipairs(implements) do
        if impl._aisAntigravity then
            return true
        end
    end
    return false
end

---Enable or disable antigravity on all attached implements.
---When enabled: bypasses PowerConsumer speed offsets and zeroes drag force.
---When disabled: restores original PowerConsumer behavior.
---@param enabled boolean True to enable, false to disable
function RmAdjustImplementSpeed:aisSetAntigravity(enabled)
    Log:trace(">>> aisSetAntigravity(enabled=%s)", tostring(enabled))

    local implements = self:aisGetSpeedLimitedImplements()
    if #implements == 0 then
        Log:debug("ANTIGRAVITY: no speed-limited implements")
        return
    end

    for _, impl in ipairs(implements) do
        impl._aisAntigravity = enabled

        -- Handle PowerConsumer friction/drag force
        local pcSpec = impl.spec_powerConsumer
        if pcSpec ~= nil then
            if enabled then
                -- Save original maxForce and zero it out
                if impl._aisOrigMaxForce == nil then
                    impl._aisOrigMaxForce = pcSpec.maxForce
                end
                pcSpec.maxForce = 0
                Log:debug("ANTIGRAVITY: %s zeroed maxForce (was %.1f kN)",
                    impl.configFileName or "unknown", impl._aisOrigMaxForce)
            else
                -- Restore original maxForce
                if impl._aisOrigMaxForce ~= nil then
                    pcSpec.maxForce = impl._aisOrigMaxForce
                    Log:debug("ANTIGRAVITY: %s restored maxForce to %.1f kN",
                        impl.configFileName or "unknown", impl._aisOrigMaxForce)
                    impl._aisOrigMaxForce = nil
                end
            end
        end
    end

    -- Update action event text
    local spec = self[RmAdjustImplementSpeed.SPEC_TABLE_NAME]
    if spec ~= nil and spec.antigravityActionEventId ~= nil then
        local newText = enabled
            and g_i18n:getText("action_aisAntigravityDisable")
            or g_i18n:getText("action_aisAntigravityEnable")
        g_inputBinding:setActionEventText(spec.antigravityActionEventId, newText)
    end

    Log:debug("ANTIGRAVITY: %s", enabled and "ENABLED" or "DISABLED")
end

-- ============================================================================
-- SPEED OVERRIDE
-- ============================================================================

---Override getRawSpeedLimit to apply speed adjustments and antigravity.
---Called on each vehicle/implement when the game queries speed limits.
---@param superFunc function Original getRawSpeedLimit function
---@return number speedLimit Adjusted speed limit in km/h
function RmAdjustImplementSpeed:getRawSpeedLimit(superFunc)
    local delta = self._aisSpeedDelta or 0

    if self._aisAntigravity then
        -- Antigravity mode: bypass PowerConsumer offsets by using raw speedLimit
        -- instead of superFunc (which includes the PowerConsumer override chain)
        local limit = self.speedLimit + delta
        return math.max(limit, RmAdjustImplementSpeed.SPEED_FLOOR)
    end

    -- Normal mode: respect the full override chain (PowerConsumer, Sprayer, etc.)
    local limit = superFunc(self)
    if delta ~= 0 then
        limit = math.max(limit + delta, RmAdjustImplementSpeed.SPEED_FLOOR)
    end
    return limit
end
