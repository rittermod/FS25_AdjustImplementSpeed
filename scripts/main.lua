--[[
    main.lua

    Main loader for AdjustImplementSpeed mod.
    Handles dependency loading, specialization registration, and type injection.

    ============================================================
    IMPORTANT: This file is a LOADER ONLY.
    ============================================================
    - It loads dependencies via source() in the correct order
    - Registers the vehicle specialization with g_specializationManager
    - Injects the specialization into vehicle types via TypeManager hook
    - All mod logic belongs in scripts/RmAdjustImplementSpeed.lua
    ============================================================

    Author: Ritter
]]

local modName = g_currentModName
local modDirectory = g_currentModDirectory

-- =============================================================================
-- INFRASTRUCTURE
-- =============================================================================

source(modDirectory .. "scripts/rmlib/RmLogging.lua")
local Log = RmLogging.getLogger("AdjustImplementSpeed")
Log:setLevel(RmLogging.LOG_LEVEL.INFO) -- Set to DEBUG/TRACE for development

-- =============================================================================
-- SPECIALIZATION REGISTRATION
-- NOTE: The specialization file is sourced by addSpecialization(), NOT manually.
-- =============================================================================

g_specializationManager:addSpecialization(
    "rmAdjustImplementSpeed",
    "RmAdjustImplementSpeed",
    Utils.getFilename("scripts/RmAdjustImplementSpeed.lua", modDirectory),
    nil
)
Log:info("AdjustImplementSpeed mod loaded - specialization registered")

-- =============================================================================
-- VEHICLE TYPE INJECTION
-- Inject specialization into all Drivable vehicle types.
-- Uses appendedFunction pattern per FS25_BulkFill / AdjustStorageCapacity.
-- =============================================================================

---Inject the specialization into all vehicle types that have Drivable
---@param typeManager TypeManager
local function injectIntoVehicleTypes(typeManager)
    if typeManager.typeName ~= "vehicle" then
        return
    end

    local specName = modName .. ".rmAdjustImplementSpeed"
    local count = 0

    -- Inject into ALL vehicle types so that getRawSpeedLimit override
    -- is present on implements (cultivators, plows, etc.), not just tractors.
    -- onRegisterActionEvents only fires on Drivable types (harmless on others).
    for typeName, typeEntry in pairs(g_vehicleTypeManager.types) do
        g_vehicleTypeManager:addSpecialization(typeName, specName)
        count = count + 1
    end

    if count > 0 then
        Log:info("Injected specialization into %d vehicle types", count)
    end
end

TypeManager.validateTypes = Utils.appendedFunction(TypeManager.validateTypes, injectIntoVehicleTypes)

-- =============================================================================
-- TESTING (conditional - tests are excluded from release builds)
-- =============================================================================

local testRunnerPath = modDirectory .. "scripts/tests/RmTestRunner.lua"
if fileExists(testRunnerPath) then
    source(testRunnerPath)
end
