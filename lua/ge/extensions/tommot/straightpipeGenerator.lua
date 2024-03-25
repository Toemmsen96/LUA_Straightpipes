local M = {}

--template
local template = nil
local templateVersion = -1
local exhaustPath = nil

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
	print("writing to: " .. path)
	if not file then 
		print("ERROR: failed to open file for writing")
		return nil 
	end
	local content = json.encode(data, { indent = not compact })
	file:write(content)
	file:close()
	return true
end

--load jbeam file from path
local function loadExistingJbeam(path)
	jbeamFile = readJsonFile(path)
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
    end
  end
  return vehicles
end

local function getstraightpipeJbeamPath(vehicleDir)
	local path = "/mods/unpacked/generatedStraightpipe/vehicles/" .. vehicleDir .. "/straightpipe/" .. vehicleDir .. "_straightpipes.jbeam"
	--log('D', 'getStraightpipeJbeamPath', "loading straightpipe path: " .. path)
	return path
end

local function loadExistingstraightpipeData(vehicleDir)
	return readJsonFile(getstraightpipeJbeamPath(vehicleDir))
end

local function makeAndSaveNewTemplate(vehicleDir, fileTemplate)
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
		print("partKey: " .. partKey)
		local newPartKey = partKey .. "_straightpipe"
		print("new partKey: " .. newPartKey)
		part.information.name = part.information.name .. " Straightpiped"
		local new_coef = 1.0
		-- add coefficient edits here
		if type(part.nodes) == "table" then
			print("found nodes in part")
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
	if type(vehicleJbeam) ~= 'table' then return nil end
	
	for partKey, part in pairs(vehicleJbeam) do
		-- is it valid?
		-- print(ends_with(part.slotType, "_exhaust"))
		if type(part.slotType) == 'table' then 
			return nil 
		end
		if ends_with(part.slotType, "_exhaust") then
			log('D', 'findExhaustPart', part.slotType.." slot found.")
			print("found exhaust slot: " .. partKey)
			return partKey
		end
	end
	return nil
end
local function loadExhaustSlot(vehicleDir)
	--first check if a file exists named vehicleDir.jbeam
	local vehJbeamPath = "/vehicles/" .. vehicleDir .. "/" .. vehicleDir .. "_exhaust.jbeam"
	local vehicleJbeam = nil
	
	if FS:fileExists(vehJbeamPath) then
		-- load it!
		log('D', 'onExtensionLoaded', "loading " .. vehicleDir .. "_exhaust.jbeam for exhaust slot data")
		vehicleJbeam = readJsonFile(vehJbeamPath)
		exhaustPath = vehJbeamPath
		
		-- is it valid?
		local exhaustPartKey = findExhaustPart(vehicleJbeam)
		if exhaustPartKey ~= nil then
			return vehicleJbeam[exhaustPartKey]
		end
	end
	
	--if it wasn't valid, look through all files in this vehicle dir
	local files = FS:findFiles("/vehicles/" .. vehicleDir, "*.jbeam", -1, true, false)
	for _, file in ipairs(files) do
		-- load it!
		vehicleJbeam = readJsonFile(file)
		
		-- is it valid?
		local exhaustPartKey = findExhaustPart(vehicleJbeam)
		if exhaustPartKey ~= nil then
			exhaustPath = file
			return exhaustPartKey
		end
	end
	
	--if all else fails, return nil
	return nil
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
		print("existing Data: " .. tostring(existingData))
	else
		--log('D', 'onExtensionLoaded', vehicleDir .. " NOT up to date, updating")
	end
	
	local exhaustSlotData = loadExhaustSlot(vehicleDir)

	if exhaustSlotData == nil then
		--log('D', 'onExtensionLoaded', "no exhaust slot found for " .. vehicleDir)
		return
	end

	local existingJbeam = loadExistingJbeam(exhaustPath)

	if existingJbeam == nil then
		log('D', 'onExtensionLoaded', "no existing jbeam found for " .. vehicleDir)
		return
	end

	

	--make modifications to the existing jbeam
	makeAndSaveNewTemplate(vehicleDir, generateStraightpipeModJbeam(existingJbeam))

end

local function generateAll()
	log('D', 'generateAll', "running generateAll()")
	for _,veh in pairs(getAllVehicles()) do
		generate(veh)
	end
	log('D', 'generateAll', "done generating")
end



local function onExtensionLoaded()
	log('D', 'onExtensionLoaded', "Mods/TommoT straightpipe Generator Loaded")
	generateAll()
end

-- functions which should actually be exported
M.onExtensionLoaded = onExtensionLoaded
M.onModDeactivated = onExtensionLoaded
M.onModActivated = onExtensionLoaded
M.onExit = deleteTempFiles

return M