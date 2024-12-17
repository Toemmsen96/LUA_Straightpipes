local M = {}
--"global" variables
local currentVersion = 1.0
--local exhaustPaths = {}

--helpers
local function isEmptyOrWhitespace(str)
    return str == nil or str:match("^%s*$") ~= nil
end

local function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

local function readJsonFile(path)
    if isEmptyOrWhitespace(path) then
        log('E', 'readJsonFile', "path is empty")
        return nil
    end
    return jsonReadFile(path)
end

local function writeJsonFile(path, data, nice)
    return jsonWriteFile(path, data, nice)
end

local function subtract_except(str, substring)
    local pattern = ".*(" .. substring .. ").*"
    local match = string.match(str, pattern)
    if match then
        return match
    else
        return ""  -- Return empty string if substring not found
    end
end

local function ends_with(str, ending)
    return subtract_except(str,ending) == ending
end
--end helpers

--load jbeam file from path
local function loadExistingJbeam(path)
	local jbeamFile = readJsonFile(path)
	if jbeamFile == nil then
		log('D', 'loadExistingJbeam', "Failed to load existing file")
		return nil
	end
	log('D', 'loadExistingJbeam', "Existing File loaded, Part names: ")
	for k,v in pairs(jbeamFile) do
		log('D', 'loadExistingJbeam', k)
	end
	return jbeamFile
end


local function getAllVehicles()
	local vehicles = {}
	for _, v in ipairs(FS:findFiles('/vehicles', '*', 0, false, true)) do
		if v ~= '/vehicles/common' then
		  table.insert(vehicles, string.match(v, '/vehicles/(.*)'))
		else
			--table.insert(vehicles, "common/" .. string.match(v, '^/vehicles/common/(.*)'))
		end
	end
	return vehicles
end

local function getstraightpipeJbeamPath(vehicleDir)
	if vehicleDir == nil then return nil end
	local path = "/mods/unpacked/generatedStraightpipe/vehicles/" .. vehicleDir .. "/straightpipe/" .. vehicleDir .. "_straightpipes.jbeam"
	--log('D', 'getStraightpipeJbeamPath', "loading straightpipe path: " .. path)
	return path
end

local function loadExistingstraightpipeData(vehicleDir)
	return readJsonFile(getstraightpipeJbeamPath(vehicleDir))
end

local function getUniqueStraightpipeJbeamPath(vehicleDir, originalFileName)
    if vehicleDir == nil or originalFileName == nil then return nil end
    local fileName = originalFileName:match("([^/]+)%.jbeam$") -- Extract the original file name without extension
    local path = "/mods/unpacked/generatedStraightpipe/vehicles/" .. vehicleDir .. "/straightpipe/" .. vehicleDir .. "_" .. fileName .. "_straightpipes.jbeam"
    return path
end

local function makeAndSaveNewJbeam(vehicleDir, fileTemplate, originalFileName)
    if fileTemplate == nil then 
        log('E', 'makeAndSaveNewJbeam', "fileTemplate is nil")
        return 
    end
    local newTemplate = deepcopy(fileTemplate)

    --save it
    local savePath = getUniqueStraightpipeJbeamPath(vehicleDir, originalFileName)
    writeJsonFile(savePath, newTemplate, true)
end

local function generateStraightpipeModJbeam(originalJbeam)
    if type(originalJbeam) ~= 'table' then return nil end
    
    local newJbeam = {}
    for partKey, part in pairs(originalJbeam) do
        -- modify component name
        if ends_with(partKey, "_straightpipe") then
            log('D', 'generateStraightpipeModJbeam', "partKey already ends with _straightpipe, skipping")
            goto continue -- Skip this part if it's already a straightpipe
        end
        local newPartKey = partKey .. "_straightpipe"
        part.information.name = part.information.name .. " Straightpiped"
        part.information.Version = 1.0  -- Add version information
         -- Define variables
		part.variables = {
            {"name", "type", "unit", "category", "default", "min", "max", "title", "description"},
            {"$afterFireAudioCoef", "range", "coef", "Exhaust", 1.0, 0.0, 1.0, "Afterfire Audio Coef", "How much audible Afterfire from the engine gets let through the exhaust.", {["stepDis"]=0.1}},
            {"$afterFireVisualCoef", "range", "coef", "Exhaust", 1.0, 0.0, 3.0, "Afterfire Visual Coef", "Visible flames and pops in the exhaust.", {["stepDis"]=0.1}},
            {"$afterFireVolumeCoef", "range", "coef", "Exhaust", 1.0, 0.0, 10.0, "Afterfire Volume Coef", "How loud pops and bangs are.", {["stepDis"]=0.1}},
            {"$afterFireMufflingCoef", "range", "coef", "Exhaust", 0.5, 0.0, 1.0, "Afterfire Muffling Coef (Inversed)", "Afterfire muffling coefficient", {["stepDis"]=0.01}},
            {"$exhaustAudioMufflingCoef", "range", "coef", "Exhaust", 0.5, 0.0, 1.0, "Exhaust Audio Muffling Coef (Inversed)", "Muffling of the engine. (Inversed)", {["stepDis"]=0.01}},
            {"$exhaustAudioGainChange", "range", "dB", "Exhaust", 3.0, -20.0, 20.0, "Exhaust Audio Gain Change", "Exhaust Noise Gain change in Decibel", {["stepDis"]=0.1}},
        }

        -- Update coefficients using variables
        if type(part.nodes) == "table" then
            for i, subnode in ipairs(part.nodes) do
                for k, v in pairs(subnode) do
                    if type(v) == "table" and v.afterFireAudioCoef then
                        print("Found exhaust nodes: " .. subnode[1]..": ".. tostring(v))
                        v.afterFireAudioCoef = "$afterFireAudioCoef"
                        v.afterFireVisualCoef = "$afterFireVisualCoef"
                        v.afterFireVolumeCoef = "$afterFireVolumeCoef"
                        v.afterFireMufflingCoef = "$afterFireMufflingCoef"
                        v.exhaustAudioMufflingCoef = "$exhaustAudioMufflingCoef"
                        v.exhaustAudioGainChange = "$exhaustAudioGainChange"
                    end
                end
            end
        end

        -- Add your code here to modify the part object
        newJbeam[newPartKey] = part  -- Update the modified part in the newJbeam table
        ::continue::
    end
    
    if next(newJbeam) == nil then
        log('E', 'generateStraightpipeModJbeam', "No valid parts found to modify")
        return nil
    end
    
    return newJbeam
end

-- part helpers
local function findExhaustPart(vehicleJbeam) 
    if type(vehicleJbeam) ~= 'table' then return {} end
    local PartKeys = {}

    for partKey, part in pairs(vehicleJbeam) do
        if type(part.slotType) == 'table' then 
            return {} 
        end
        local slotTypeLower = string.lower(part.slotType)
		if string.find(slotTypeLower, "straightpipe") then
			log('D', 'findExhaustPart', "Part is already a straightpipe, skipping")
			goto continue
		elseif string.find(slotTypeLower, "exhaust") or string.find(slotTypeLower, "muffler") then
			table.insert(PartKeys, partKey)
		end
		::continue::
    end
    if #PartKeys == 0 then
        --log('W', 'findExhaustPart', "No exhaust or muffler slot found for ")
        return nil
    else
        log('D', 'findExhaustPart', "PartKeys found: " .. table.concat(PartKeys, ", "))
        return PartKeys
    end
end

--load exhaust slot
local function loadExhaustSlot(vehicleDir)
    local exhaustPaths = {}
    local files = FS:findFiles("/vehicles/" .. vehicleDir, "*.jbeam", -1, true, false)
    for _, file in ipairs(files) do
        if string.find(file, "generalEngineSwap") then
            log('D','loadExhaustSlot', "ingoring gES")
        else
            local vehicleJbeam = readJsonFile(file)
            local exhaustPartKeys = findExhaustPart(vehicleJbeam)
            if exhaustPartKeys ~= nil and #exhaustPartKeys > 0 then
			    log('D', 'loadExhaustSlot', "exhaust slot found in " .. file)
                table.insert(exhaustPaths, file)
            end
        end
    end
    return exhaustPaths
end

local function getSlotTypes(slotTable)
	local slotTypes = {}
	for i, slot in pairs(slotTable) do
		if i > 1 then
			local slotType = slot[1]
			table.insert(slotTypes, slotType)
		end
	end
	return slotTypes
end

--generation stuff
local function generate(vehicleDir)
    local existingData = loadExistingstraightpipeData(vehicleDir)
    if existingData ~= nil then
        for partKey, part in pairs(existingData) do
            if part.information.Version == currentVersion then
                log('D', 'onExtensionLoaded', vehicleDir .. " up to date")
                return
            end
        end
    end

    local exhaustSlotData = loadExhaustSlot(vehicleDir)
    if #exhaustSlotData == 0 then
        log('I', 'onExtensionLoaded', "no exhaust slot found for " .. vehicleDir)
        return
    end

    for _, exhaustPath in ipairs(exhaustSlotData) do
        local existingJbeam = loadExistingJbeam(exhaustPath)
        if existingJbeam == nil then
            log('E', 'onExtensionLoaded', "no existing jbeam found for " .. vehicleDir)
        else
            --log('D', 'onExtensionLoaded', "existing jbeam loaded for " .. vehicleDir.. " at path: " .. exhaustPath .. " with keys: " .. table.concat(existingJbeam, ", "))
            local newJbeam = generateStraightpipeModJbeam(existingJbeam)
            if newJbeam == nil then
                log('E', 'onExtensionLoaded', "failed to generate new jbeam for " .. vehicleDir)
            else
                makeAndSaveNewJbeam(vehicleDir, newJbeam, exhaustPath)
            end
        end
    end
end

local function generateAll()
	log('D', 'generateAll', "running generateAll()")
	for _,veh in pairs(getAllVehicles()) do
		generate(veh)
	end
	--[[
	generate("/vehicles/common/etk")
	generate("/vehicles/common/pickup")
	generate("/vehicles/common/pigeon")
	generate("/vehicles/common/van")
	generate("/vehicles/common/engines")
	]]--
	log('D', 'generateAll', "done generating")
end



local function onExtensionLoaded()
	log('D', 'onExtensionLoaded', "Mods/TommoT straightpipe Generator Loaded")
	generateAll()
end

local function deleteTempFiles()
	--delete all files in /mods/unpacked/generatedModSlot
	log('W', 'deleteTempFiles', "Deleting all files in /mods/unpacked/generatedStraightpipe")
	local files = FS:findFiles("/mods/unpacked/generatedStraightpipe", "*", -1, true, false)
	for _, file in ipairs(files) do
		FS:removeFile(file)
	end
	log('W', 'deleteTempFiles', "Done")
end
-- functions which should actually be exported
M.onExtensionLoaded = onExtensionLoaded
M.onModDeactivated = deleteTempFiles
M.onModActivated = onExtensionLoaded
M.onExit = deleteTempFiles

return M