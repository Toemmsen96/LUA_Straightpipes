local M = {}

--template
local template = nil
local templateVersion = -1
local currentVersion = 1.0
--local exhaustPaths = {}

--helpers
local function ends_with(str, ending)
   return ending == "" or str:sub(-#ending) == ending
end

local json = require 'dkjson'  -- imports required json lib (see /lua/common/extensions/LICENSE.txt)

--read json files
local function readJsonFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content and json.decode(content) or nil
end
--write json files
local function writeJsonFile(path, data, compact)
	local file = io.open(path, "w")
	log("I","WritingJbeam","writing to: " .. path)
	if not file then 
		log("E","WritingJbeam","ERROR: failed to open file for writing")
		return nil 
	end
	local content = json.encode(data, { indent = not compact })
	file:write(content)
	file:close()
	return true
end

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
	for _, v in ipairs(FS:findFiles('/vehicles', '*', -1, false, true)) do
		if not string.match(v, '^/vehicles/common/') then
			local vehicleName = string.match(v, '/vehicles/(.*)')
			if vehicleName then
				table.insert(vehicles, vehicleName)
			end
		else
			local commonVehicleName = string.match(v, '^/vehicles/common/(.*)')
			if commonVehicleName then
				table.insert(vehicles, "common/" .. commonVehicleName)
			end
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

local function makeAndSaveNewTemplate(vehicleDir, fileTemplate)
	if fileTemplate == nil then 
		log('E', 'makeAndSaveNewTemplate', "fileTemplate is nil")
		return 
	end
	local newTemplate = deepcopy(fileTemplate)

	--save it
	local savePath = getstraightpipeJbeamPath(vehicleDir)
	writeJsonFile(savePath, newTemplate, true)
end


local function generateStraightpipeModJbeam(originalJbeam)
	if type(originalJbeam) ~= 'table' then return nil end
	
	local newJbeam = {}
	for partKey, part in pairs(originalJbeam) do
		-- modify component name
		--print("partKey: " .. partKey)
		if ends_with(partKey,"_straightpipe") then
			log('D', 'generateStraightpipeModJbeam', "partKey already ends with _straightpipe, skipping")
			return nil
		end
		local newPartKey = partKey .. "_straightpipe"
		--print("new partKey: " .. newPartKey)
		part.information.name = part.information.name .. " Straightpiped"
		part.information.Version = 1.0  -- Add version information
		local new_coef = 1.0 --makes everything maxed out
		-- add coefficient edits here
		if type(part.nodes) == "table" then
			--print("found nodes in part")
			for i, subnode in ipairs(part.nodes) do
				for k, v in pairs(subnode) do
					--print("subnode[".. k .."]: " .. tostring(v))
					if type(v) == "table" and v.afterFireAudioCoef then
						print("Found exhaust nodes: " .. subnode[1]..": ".. tostring(v))
						v.afterFireAudioCoef = new_coef
						v.afterFireVisualCoef = new_coef
						v.afterFireVolumeCoef = new_coef
						v.afterFireMufflingCoef = 0.0
						v.exhaustAudioMufflingCoef = 0.0
						v.exhaustAudioGainChange = 3.0
					end
				end
				--print("subnode: " .. type(subnode))
			end
		end

		-- Add your code here to modify the part object
		newJbeam[newPartKey] = part  -- Update the modified part in the newJbeam table
	end
	originalJbeam = newJbeam  -- Replace the original table with the new one
	
	return originalJbeam
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



-- part helpers
local function findExhaustPart(vehicleJbeam) 
	if type(vehicleJbeam) ~= 'table' then return {} end
	local PartKeys = {}

	for partKey, part in pairs(vehicleJbeam) do
		if type(part.slotType) == 'table' then 
			return {} 
		end
		if ends_with(part.slotType, "_exhaust") then
			--log('D', 'findExhaustPart', part.slotType.." slot found.")
			--log('D', "found exhaust slot: " .. partKey)
			table.insert(PartKeys, partKey)
		end
		if ends_with(part.slotType, "_muffler") then
			--log('D', 'findExhaustPart', part.slotType.." slot found.")
			--log('D', "found muffler slot: " .. partKey)
			table.insert(PartKeys, partKey)
		end
	end
	if #PartKeys == 0 then
		log('W', 'findExhaustPart', "No exhaust slot found.")
		return nil
	else
		log('D', 'findExhaustPart', "PartKeys found: " .. table.concat(PartKeys, ", "))
		return PartKeys
	end
end

--load exhaust slot
local function loadExhaustSlot(vehicleDir)
	--first check if a file exists named vehicleDir.jbeam
	local vehJbeamPath = "/vehicles/" .. vehicleDir .. "/" .. vehicleDir .. "_exhaust.jbeam"
	local vehicleJbeam = nil
	local exhaustPaths = {}
	--[[
	if FS:fileExists(vehJbeamPath) then
		-- load it!
		log('D', 'onExtensionLoaded', "loading " .. vehicleDir .. "_exhaust.jbeam for exhaust slot data")
		vehicleJbeam = readJsonFile(vehJbeamPath)
		exhaustPath = vehJbeamPath
		
		-- is it valid?
		local exhaustPartKeys = findExhaustPart(vehicleJbeam)
		if exhaustPartKeys ~= nil then
			return vehicleJbeam[exhaustPartKey]
		end
	end
	]]--
	--if it wasn't valid, look through all files in this vehicle dir
	local files = FS:findFiles("/vehicles/" .. vehicleDir, "*.jbeam", -1, true, false)
	for _, file in ipairs(files) do
		-- load it!
		local vehicleJbeam = readJsonFile(file)
		
		-- is it valid?
		local exhaustPartKey = findExhaustPart(vehicleJbeam)
		if exhaustPartKey ~= nil and #exhaustPartKey > 0 then
			if #exhaustPaths > 0 and exhaustPaths[#exhaustPaths]==file then
				--print("exhaust slot already found, skipping")
				log('D', 'loadExhaustSlot', "exhaust slot already found, skipping file: " .. file)
			else
				--print("exhaust slot found, adding file: " .. file)
				table.insert(exhaustPaths,file)
			end
		else
			--print("exhaust slot not found, skipping file: " .. file)
		end	
	end
	--print("exhaust paths: " .. table.concat(exhaustPaths, ", "))
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
		log('D', 'onExtensionLoaded', vehicleDir .. " exists.")
		log("I", "existing Data: " .. tostring(existingData))
		for partKey, part in pairs(existingData) do
			log('D', 'VersionCheck', "Part: " .. partKey)
			log("D", "VersionCheck", "Version: ".. part.information.Version)
			if part.information.Version == currentVersion then
				log('D', 'onExtensionLoaded', vehicleDir .. " up to date")
				return
			end
		end
		
	else
		--log('D', 'onExtensionLoaded', vehicleDir .. " NOT up to date, updating")
	end
	
	local exhaustSlotData = loadExhaustSlot(vehicleDir)

	if exhaustSlotData[1] == nil then
		--log('I', 'onExtensionLoaded', "no exhaust slot found for " .. vehicleDir)
		return
	end

	for _, exhaustPath in ipairs(exhaustSlotData) do
		local existingJbeam = loadExistingJbeam(exhaustPath)

		if existingJbeam == nil then
			log('E', 'onExtensionLoaded', "no existing jbeam found for " .. vehicleDir)
			-- continue with the next exhaust path
		else
			log('D', 'onExtensionLoaded', "existing jbeam loaded for " .. vehicleDir.. " at path: " .. exhaustPath .. " with keys: " .. table.concat(existingJbeam, ", "))
			-- make modifications to the existing jbeam
			local newJbeam = generateStraightpipeModJbeam(existingJbeam)
			if newJbeam == nil then
				log('E', 'onExtensionLoaded', "failed to generate new jbeam for " .. vehicleDir)
			else
				-- save the new jbeam
				makeAndSaveNewTemplate(vehicleDir, newJbeam)
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