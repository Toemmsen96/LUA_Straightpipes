local M = {}
M.type = "auxiliary"

local closedMufflingOffset = 0
local closedGainOffset = 0
local openMufflingOffset = -10
local openGainOffset = 15
local currentState = "valveClosed"

-- Reuse the existing exhaust function
local function setExhaustGainMufflingOffset(engineName, mufflingOffset, gainOffset)
    log('I', 'valvedExhausts', 'Setting exhaust values for ' .. engineName .. ': muffling=' .. mufflingOffset .. ', gain=' .. gainOffset)
    local engine = powertrain.getDevice(engineName)
    if not engine or not engine.setExhaustGainMufflingOffset then
        log('E', 'valvedExhausts', 'Engine not found or missing setExhaustGainMufflingOffset function: ' .. tostring(engineName))
        return
    end
    engine:setExhaustGainMufflingOffset(mufflingOffset, gainOffset)
    log('D', 'valvedExhausts', 'Exhaust values set successfully')
end

-- Create states for toggling
local exhaustStates = {
    valveClosed = {
        mufflingOffset = closedMufflingOffset,
        gainOffset = closedGainOffset
    },
    valveOpen = {
        mufflingOffset = openMufflingOffset,
        gainOffset = openGainOffset
    }
}

local function setValveGainValues(newClosedMuffling, newClosedGain, newOpenMuffling, newOpenGain)
    closedMufflingOffset = newClosedMuffling
    closedGainOffset = newClosedGain
    openMufflingOffset = newOpenMuffling
    openGainOffset = newOpenGain
    exhaustStates.valveClosed.mufflingOffset = closedMufflingOffset
    exhaustStates.valveClosed.gainOffset = closedGainOffset
    exhaustStates.valveOpen.mufflingOffset = openMufflingOffset
    exhaustStates.valveOpen.gainOffset = openGainOffset
    dump(exhaustStates)
end

-- Table to hold our button data
local simpleControlButtons = {}

local function updateSimpleControlButton(buttonData)
    if not extensions.ui_simplePowertrainControl then
        log('E', 'valvedExhausts', 'ui_simplePowertrainControl extension not available')
        return
    end
    extensions.ui_simplePowertrainControl.setButton(buttonData.id, buttonData.uiName, buttonData.icon, buttonData.currentColor, nil, buttonData.onClick)
end

local function setSimpleControlButton(id, buttonUIName, icon, color, offColor, offColorElectric, onClick, remove)
    if not id then 
        log('E', 'valvedExhausts', 'Invalid button ID provided')
        return
    end
    
    if remove then
        simpleControlButtons[id] = nil
        if extensions.ui_simplePowertrainControl then
            extensions.ui_simplePowertrainControl.setButton(id, nil, nil, nil, nil, nil, true)
        end
    else
        simpleControlButtons[id] = simpleControlButtons[id] or {}
        simpleControlButtons[id].id = id
        simpleControlButtons[id].uiName = buttonUIName
        simpleControlButtons[id].icon = icon
        simpleControlButtons[id].lastColor = nil
        simpleControlButtons[id].currentColor = currentState == "valveOpen" and color or (offColor or "343434")
        simpleControlButtons[id].color = color
        simpleControlButtons[id].offColor = offColor or "343434"
        simpleControlButtons[id].offColorElectric = offColorElectric
        simpleControlButtons[id].onClick = onClick or string.format("controller.getController(%q).toggleExhaustState()", M.name)
        updateSimpleControlButton(simpleControlButtons[id])
    end
end

local function updateSimpleControlButtons()
    for id, buttonData in pairs(simpleControlButtons) do
        -- Update button color based on current valve state
        buttonData.currentColor = currentState == "valveOpen" and buttonData.color or buttonData.offColor
        updateSimpleControlButton(buttonData)
        log('D', 'valvedExhausts', 'Updated button ' .. id .. ' color to ' .. buttonData.currentColor)
    end
end

-- Function to toggle exhaust state
local function toggleExhaustState()
    local oldState = currentState
    currentState = currentState == "valveClosed" and "valveOpen" or "valveClosed"
    log('I', 'valvedExhausts', 'Exhaust state toggled from ' .. oldState .. ' to ' .. currentState)
    guihooks.message('Exhaust state changed to ' .. currentState)
    
    local state = exhaustStates[currentState]
    setExhaustGainMufflingOffset("mainEngine", state.mufflingOffset, state.gainOffset)
    
    -- Update button colors after state change
    updateSimpleControlButtons()
    
    -- Return the current state for UI purposes
    return currentState
end

-- Function to set specific exhaust state
local function setExhaustState(state)
    log('I', 'valvedExhausts', 'setExhaustState called with state: ' .. tostring(state))
    if exhaustStates[state] then
        currentState = state
        local settings = exhaustStates[state]
        setExhaustGainMufflingOffset("mainEngine", settings.mufflingOffset, settings.gainOffset)
        
        -- Update button colors after state change
        updateSimpleControlButtons()
    else
        log('E', 'valvedExhausts', 'Invalid exhaust state requested: ' .. tostring(state))
    end
end

-- Alternative integration with simpleControlButton directly
local function registerAsSimpleButton() 
    log('I', 'valvedExhausts', 'Registering exhaust as simple button')

    -- Register the button directly
    setSimpleControlButton(
        "exhaust_valve",                -- id
        "Exhaust Valve",                -- buttonUIName
        "systems_exhaust-valve",        -- icon
        "ff0000",                       -- color (red for open)
        "343434",                       -- offColor (grey for closed)
        nil,                            -- offColorElectric (no electrical control)
        string.format("controller.getController(%q).toggleExhaustState()", M.name)  -- onClick
    )
    
    log('I', 'valvedExhausts', 'Exhaust button registered')
end

-- Function to initialize module
local function init(jbeamData)
    log('I', 'valvedExhausts', 'Initializing valvedExhausts module')
    if jbeamData.enabled == 0 then
        log('I', 'valvedExhausts', 'Module disabled in jbeam')
        return false
    end
    
    -- Check for proper jbeam config
    if jbeamData.valveClosed and jbeamData.valveOpen then
        setValveGainValues(
            jbeamData.valveClosed.mufflingOffset or 0,
            jbeamData.valveClosed.gainOffset or 0,
            jbeamData.valveOpen.mufflingOffset or -10,
            jbeamData.valveOpen.gainOffset or 15
        )
    else
        log('W', 'valvedExhausts', 'Missing valve state configurations in jbeam data')
    end
    
    -- Register simple button
    registerAsSimpleButton()
    
    -- Set initial state
    setExhaustState("valveClosed")
    
    log('I', 'valvedExhausts', 'Module initialized')
    return true
end

-- Function called every frame
local function updateGFX(dt)
    -- This runs every frame - we could update the button here,
    -- but it's more efficient to update only when the state changes
end

-- Export functions
M.init = init
M.updateGFX = updateGFX
M.toggleExhaustState = toggleExhaustState
M.setExhaustState = setExhaustState
M.setValveGainValues = setValveGainValues
M.updateSimpleControlButtons = updateSimpleControlButtons
M.setSimpleControlButton = setSimpleControlButton

log('I', 'valvedExhausts', 'Module loaded')
return M