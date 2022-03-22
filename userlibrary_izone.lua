------------------------------------------------------------
-- nac-izone
-- User Library

-- Supports both resident and event-based invocation to provide full two-way control between C-Bus and the iZone system.

-- * Auto-create objects in the script so we aren't dependent on the user creating them.
------------------------------------------------------------

----------------------------------------
-- SCRIPT CONFIGURATION
-- You should review and change these as needed
----------------------------------------

-- The IP address of the iZone Wifi Bridge
local IZONE_IP = "192.168.1.19"

-- The number of zones defined in your iZone system
local IZONE_ZONES = 7

----------
-- C-Bus Lighting-like Application
-- This creates a two-way mapping so that you can control the A/C functions from C-Bus and from visualisations
-- NOTE: These must be unique and not conflict with any other units or scripts
-- NOTE: They must also be created on the Objects page and set to an initial value otherwise they will not work!

-- The Application for the following groups (default is 'Heating')
local CBUS_APP = 136

-- The C-Bus Group to map to the iZone Aircon On/Off state
local CBUS_SYSTEMON_GROUP = 1

-- The C-Bus Group to map to the iZone Aircon Mode
local CBUS_MODE_GROUP = 2

-- The C-Bus Group to map to the iZone Aircon Fan state
local CBUS_FAN_GROUP = 3

-- The C-Bus Groups to map to each of the Zones' On/Off states
-- Note: the number of these must equal or exceed IZONE_ZONES
local CBUS_ZONE_GROUPS = { 11, 12, 13, 14, 15, 16, 17, 18 }

----------
-- NAC User Param application
-- This maintains values in realtime so they can be displayed in visualisations and charts
-- NOTE: These must be unique and not conflict with any other units or scripts
-- NOTE: They must also be created on the Objects page and set to an initial value otherwise they will not work!
local CBUS_USERPARAM_APP = 250
local CBUS_USERPARAM_GA_SETPOINT = "0/250/0"
local CBUS_USERPARAM_NAME_UPDATED = "acupdated"
local CBUS_USERPARAM_NAME_SETPOINT = "acsetpoint"
local CBUS_USERPARAM_NAME_SETPOINTACTIVE = "acsetpointactive"
local CBUS_USERPARAM_NAME_TEMP = "actemp"

----------
-- C-Bus Measurement Application
-- This produces a report at more leisurely intervals that can be used for charting over longer periods of time
-- NOTE: These must be unique and not conflict with any other units or scripts
-- NOTE: They must also be created on the Objects page and set to an initial value otherwise they will not work!
local CBUS_MEASUREMENT_APP = 228
local CBUS_MEASUREMENT_DEVICE = 1
local CBUS_MEASUREMENT_CHANNEL_SETPOINT = 1
local CBUS_MEASUREMENT_CHANNEL_TEMP = 2
local CBUS_MEASUREMENT_CHANNEL_SETPOINTACTIVE = 3

-- The time in minutes between each Measurement update
local CBUS_MEASUREMENT_INTERVAL_MINS = 5


----------------------------------------
-- SCRIPT CONSTANTS
-- You should not need to change these
----------------------------------------

local CBUS_MEASUREMENT_UNIT_CELSIUS = 0

local CBUS_USERPARAM_NAME_DEBUGLOGGING = "Debug Logging"

-- iZone often ignores a POST command.  It has some really bad timing issue or race condition internally.
-- To work around this fatal flaw we send a POST several times.  This variable determines the number of times.
-- 5 attempts seems to succeed about 2/3 of the time.
-- 8 attempts seems to succeed about 90% of the time.
-- 10 attempts seems to be pretty reliable.
local IZONE_POST_ATTEMPTS = 10

-- Keywords used by the iZone API.  These must be in the same order as the corresponding C-Bus Levels, starting from 0, 1, 2, 3...
local AC_MODE_NAMES = { "cool", "heat", "vent", "dry", "auto" }
local AC_FAN_NAMES = { "auto", "low", "med", "high" }
local AC_FAN_NAMES_POST = { "auto", "low", "medium", "high" }

----------------------------------------
-- SCRIPT BEGINS
-- Here be dragons
----------------------------------------

-- P is the private package, exposed as 'izone' library
local P = {}
izone = P

-- UTILITY FUNCTIONS

local logbuildbuffer = {}

local function logbuild(str)
	logbuildbuffer[#logbuildbuffer+1]=str
end

local function logflush()
  if ( #logbuildbuffer ~= 0 ) then
    log(table.concat(logbuildbuffer, "\n"))
  	logbuildbuffer = {}
  end
end

local function isDebuggingEnabled()
  return toboolean( GetUserParam(0, CBUS_USERPARAM_NAME_DEBUGLOGGING) )
end

local function debuglog(str)
  if ( isDebuggingEnabled() ) then
    log(str)
  end
end

local function debuglogbuild(str)
  if ( isDebuggingEnabled() ) then
    logbuild(str)
  end
end

local function debuglogflush()
  if ( isDebuggingEnabled() ) then
    logflush()
  end
end


--[[
SetpointActive object: data = "26"
pollinterval = ""
updatetime = "1517922475"
datatype = "14"
decoded = "true"
disablelog = "0"
tagcache = ""
id = "4194304003"
readoninit = "0"
datahex = "41D00000"
units = ""
value = "26"
highpriolog = "0"
comment = ""
address = "0/250/3"
export = "0"
]]--

local function clearObject(name)
  local obj = grp.find(name)
  if ( obj ~= nil ) then
    grp.write(name,0/0)
  end
end

local function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        table.insert(sb, "{\n");
        table.insert(sb, table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        table.insert(sb, "}\n");
      elseif "number" == type(key) then
        table.insert(sb, string.format("\"%s\"\n", tostring(value)))
      else
        table.insert(sb, string.format(
            "%s = \"%s\"\n", tostring (key), tostring(value)))
       end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

local function tostring2( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return table_print(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
    end
end

-- C-BUS CONVERSION FUNCTIONS

local function table_getIndex(table, value)
  for idx, val in ipairs(table) do
    	if val == value then
      	return idx
      end
  end
end

function P.ModeToLevel(acmode)
  local idx = table_getIndex(AC_MODE_NAMES, acmode)
  if ( idx ~= nil ) then
    return idx - 1
  else
    return nil
  end
end

function P.LevelToMode(cbuslevel)
  return AC_MODE_NAMES[cbuslevel + 1]
end

function P.FanToLevel(acfan)
  local idx = table_getIndex(AC_FAN_NAMES, acfan)
  if ( idx ~= nil ) then
    return idx - 1
  else
    return nil
  end
end

function P.LevelToFan(cbuslevel)
  return AC_FAN_NAMES[cbuslevel + 1]
end



-- unused function
-- cbusLevel = (acLevel * 10 ) - 100
-- AC=10.0 => C-Bus=0, AC=35.5 => C-Bus=255
function P.TempToLevel(actemp) 
  return ( actemp * 10 ) - 100
end

-- unused function
-- AcLevel = (cbusLevel / 10 ) + 10
-- C-Bus=0 => AC=10.0, C-Bus=255 => AC=35.5
function P.LevelToTemp(cbuslevel) 
  return ( cbuslevel / 10 ) + 10  
end

-- C-BUS FUNCTIONS

local function GroupAddressMatches(value,net,app,group)
  return value == net.."/"..app.."/"..group
end

local function cbus_GetState(app, group)
  return GetCBusState(0, app, group)
end

local function cbus_GetLevel(app, group)
  return GetCBusLevel(0, app, group)
end

local function cbus_SetState(app, group, state)
  log("Setting C-Bus Group "..app.."/"..group.." State to "..tostring(state).."...")
  SetCBusState(0, app, group, state)
end

local function cbus_SetLevel(app, group, level)
  log("Setting C-Bus Group "..app.."/"..group.." Level to "..tostring(level).."...")
  SetCBusLevel(0, app, group, level,0)
end

function P.GetCbusSystemSettings() 
  local result = {}
  result["SystemOn"] = cbus_GetState(CBUS_APP, CBUS_SYSTEMON_GROUP)
  local cbusModeLevel = cbus_GetLevel(CBUS_APP, CBUS_MODE_GROUP)
  result["SystemMode"] = P.LevelToMode(cbusModeLevel)
  result["SystemModeAsLevel"] = cbusModeLevel
  local cbusFanLevel = cbus_GetLevel(CBUS_APP, CBUS_FAN_GROUP)
  result["SystemFan"] = P.LevelToFan(cbusFanLevel)
  result["SystemFanAsLevel"] = cbusFanLevel
  return result
end

-- iZONE API FUNCTIONS

local http = require("socket.http")
local json = require("json")

-- Get data from the specified endpoint
function P.Get(endpoint)
	local result,content,header = http.request('http://' .. IZONE_IP .. '/' .. endpoint )
  return result
end


-- Get System Settings data
function P.GetSystemSettings() 
  local result = {}
  local httpresult = P.Get("SystemSettings")
  local httptable = json.decode(httpresult)
  debuglog(httptable)
  result["SystemOn"] = ( httptable["SysOn"] == "on" )
  result["SystemMode"] = ( httptable["SysMode"] )
  result["SystemFan"] = ( httptable["SysFan"] )
  result["Setpoint"] = ( httptable["Setpoint"] )
  result["Temp"] = ( httptable["Temp"] )
  result["ZoneCount"] = ( httptable["NoOfZones"] )
  result["FanAuto"] = ( httptable["FanAuto"] )
  return result
end


-- Get Zone data
-- NOTE: This always returns details for zones 1..8
-- TODO: Perform smarter queries based on IZONE_ZONES, e.g. calling Zones9_12 etc.
function P.GetZones() 
  local result = {}
  
  local httpresult = P.Get("Zones1_4")
  local httptable = json.decode(httpresult)
  debuglog(httptable)
  for httptableindex = 1,4,1
  do
    local resultitem = {}
    resultitem["Number"] = httptableindex
    resultitem["Name"] = httptable[httptableindex]["Name"]
    resultitem["On"] = ( httptable[httptableindex]["Mode"] == "open" )
    table.insert(result, resultitem)
  end

  local httpresult = P.Get("Zones5_8")
  local httptable = json.decode(httpresult)
  debuglog(httptable)
  for httptableindex = 1,4,1
  do
    local resultitem = {}
    resultitem["Number"] = httptableindex + 4
    resultitem["Name"] = httptable[httptableindex]["Name"]
    resultitem["On"] = ( httptable[httptableindex]["Mode"] == "open" )
    table.insert(result, resultitem)
  end

 
  return result
end

-- Post a command to the system
-- NOTE: The iZone system misses a lot of commands. Tweak the repeatcount until it works.
function P.Post(endpoint, body, repeatcount)
  local url = 'http://' .. IZONE_IP .. '/' .. endpoint
  log( "POST "..repeatcount.."x :\n"..url.."\n"..body )
  for i = 1,repeatcount,1
  do 
		local result,content,header = http.request(url, body)
  end
  return result
end

-- RESIDENT SCRIPT FUNCTIONS
-- Create a resident script and add a single line to call the below.

function P.Resident_Poll()
  
  local ac = P.GetSystemSettings()
  ac["SystemModeAsLevel"] = P.ModeToLevel(ac["SystemMode"])
  ac["SystemFanAsLevel"] = P.FanToLevel(ac["SystemFan"])
  debuglog(ac)

  -- Update the user parameters as often as we can, for display on screen
  debuglogbuild("Updating user parameters...")
  storage.set("izone.disable_event_handler.setpoint", true)
  SetUserParam(0, CBUS_USERPARAM_NAME_SETPOINT, tostring(ac["Setpoint"]))
  debuglogbuild("Setpoint: "..ac["Setpoint"])
  SetUserParam(0, CBUS_USERPARAM_NAME_TEMP, tostring(ac["Temp"])) 
	debuglogbuild("Temp: "..ac["Temp"])
  local nowtext = os.date("%H:%M:%S, %d %b")
  SetUserParam(0, CBUS_USERPARAM_NAME_UPDATED, nowtext) 
  debuglogbuild("Updated: "..nowtext)
  -- Update the setpointactive for graphing
  if ( ac["SystemOn"] == true ) then
  	SetUserParam(0, CBUS_USERPARAM_NAME_SETPOINTACTIVE, tostring(ac["Setpoint"]))
    debuglogbuild("SetpointActive: "..ac["Setpoint"])
  else
    -- logbuild("SetpointActive: nil")
    -- SetUserParam(0, CBUS_USERPARAM_NAME_SETPOINTACTIVE, nil)
    clearObject("0/250/3")
    debuglogbuild("SetpointActive object: "..tostring2(grp.find("0/250/3")))
  end
  debuglogflush()

  -- Send a measurement event at specific intervals, for charting
  local lasttime = storage.get('lastmeasurementtimestamp', 0)
  local thistime = os.time()  -- lua's time resolution is only in seconds 
  if ( lasttime > thistime ) then 
    lasttime = 0 -- in case the timestamp jumps into the future (it happens sometimes)
  end
  local interval = CBUS_MEASUREMENT_INTERVAL_MINS * 60  
  debuglogbuild("Measurement: lasttime=" .. tostring(lasttime) .. " thistime="..tostring(thistime).." interval=" .. tostring(interval) )
  if ( thistime > ( lasttime + interval ) ) then
    debuglogbuild("Sending Measurement events...")
    lasttime = thistime
    SetCBusMeasurement(0, CBUS_MEASUREMENT_DEVICE, CBUS_MEASUREMENT_CHANNEL_SETPOINT, ac["Setpoint"], CBUS_MEASUREMENT_UNIT_CELSIUS) 
    SetCBusMeasurement(0, CBUS_MEASUREMENT_DEVICE, CBUS_MEASUREMENT_CHANNEL_TEMP, ac["Temp"], CBUS_MEASUREMENT_UNIT_CELSIUS) 
    if ( ac["SystemOn"] == true ) then
    	SetCBusMeasurement(0, CBUS_MEASUREMENT_DEVICE, CBUS_MEASUREMENT_CHANNEL_SETPOINTACTIVE, ac["Setpoint"], CBUS_MEASUREMENT_UNIT_CELSIUS) 
    else
      debuglogbuild("Setpoint Active : trying to set set to nil so it doesn't plot on trend")
      clearObject("0/"..CBUS_MEASUREMENT_APP.."/"..CBUS_MEASUREMENT_DEVICE.."/"..CBUS_MEASUREMENT_CHANNEL_SETPOINTACTIVE)
    end
    -- set storage variable myobjectdata to a specified value (e.g. 127)
    storage.set('lastmeasurementtimestamp', lasttime)
  end
  debuglogflush()

  -- Retrieve the C-Bus groups

  debuglogbuild("Updating lighting-like groups...")
  local cbus = P.GetCbusSystemSettings()
  debuglogbuild("System On : ac=" .. tostring(ac["SystemOn"]) .. " cbus=" .. tostring(cbus["SystemOn"]) )
  debuglogbuild("System Mode : ac=" .. tostring(ac["SystemMode"]) .. " ("..tostring(ac["SystemModeAsLevel"])..") cbus=" .. tostring(cbus["SystemMode"]).. " ("..tostring(cbus["SystemModeAsLevel"])..")" )
  local acFanLevel = P.FanToLevel(ac["SystemFan"])
  debuglogbuild("System Fan : ac=" .. tostring(ac["SystemFan"]) .. " ("..tostring(ac["SystemFanAsLevel"])..") cbus=" .. tostring(cbus["SystemFan"]).." (" .. tostring(cbus["SystemFanAsLevel"])..")" )

--[[
	local cbusSetpointLevel = cbus_GetLevel(SYSTEMSETPOINT_APP, SYSTEMSETPOINT_GROUP)
  local cbusSetpointTemp = CbusLevelToAcTemp(cbusSetpointLevel)
  local acSetpointLevel = AcTempToCbusLevel(ac["Setpoint"])
  log("System Setpoint : ac=" .. tostring(ac["Setpoint"]) .. " ("..tostring(acSetpointLevel)..") cbus=" .. tostring(cbusSetpointTemp).. " (".. tostring(cbusSetpointLevel)..")" )

  local cbusTempLevel = cbus_GetLevel(SYSTEMTEMP_APP, SYSTEMTEMP_GROUP)
  local cbusTemp = CbusLevelToAcTemp(cbusTempLevel)
  local acTempLevel = AcTempToCbusLevel(ac["Temp"])
  log("System Current Temperature : ac=" .. tostring(ac["Temp"]) .. " ("..tostring(acTempLevel)..") cbus=" .. tostring(cbusTemp).. " (".. tostring(cbusTempLevel)..")" )
]]

  local acz = P.GetZones()
  debuglog(acz)
  
  local acZoneCount = ac["ZoneCount"]  
  for zoneIndex = 1,acZoneCount,1 
  do
    local cbusZoneOn = cbus_GetState(CBUS_APP, CBUS_ZONE_GROUPS[zoneIndex])
    local acZoneOn = acz[zoneIndex]["On"]
    debuglogbuild("Zone " .. zoneIndex .. " On : ac=" .. tostring(acZoneOn) .. " cbus=" .. tostring(cbusZoneOn))
  end
  
  logflush()
  
  -- Update the C-Bus groups, if needed
  
  if ( ac["SystemOn"] ~= cbus["SystemOn"] ) then
    storage.set("izone.disable_event_handler.systemon", true)
    cbus_SetState(CBUS_APP, CBUS_SYSTEMON_GROUP, ac["SystemOn"])
  end

  if ( ac["SystemMode"] ~= cbus["SystemMode"] ) then
    storage.set("izone.disable_event_handler.systemmode", true)
    cbus_SetLevel(CBUS_APP, CBUS_MODE_GROUP, ac["SystemModeAsLevel"])
  end

  if ( ac["SystemFanAsLevel"] ~= nil and ac["SystemFanAsLevel"] ~= cbus["SystemFanAsLevel"] ) then
    storage.set("izone.disable_event_handler.systemfan", true)
    cbus_SetLevel(CBUS_APP, CBUS_FAN_GROUP, ac["SystemFanAsLevel"])
  end

--[[
  if ( acSetpointLevel ~= nil and acSetpointLevel ~= cbusSetpointLevel ) then
    cbus_SetLevel(SYSTEMSETPOINT_APP, SYSTEMSETPOINT_GROUP, acSetpointLevel)
  end
  
  if ( acTempLevel ~= nil and acTempLevel ~= cbusTempLevel ) then
    cbus_SetLevel(SYSTEMTEMP_APP, SYSTEMTEMP_GROUP, acTempLevel)
  end
]]
  
  for zoneIndex = 1,acZoneCount,1 
  do
    local cbusZoneOn = cbus_GetState(CBUS_APP, CBUS_ZONE_GROUPS[zoneIndex])
    local acZoneOn = acz[zoneIndex]["On"]
    if ( acZoneOn ~= cbusZoneOn ) then
      storage.set("izone.disable_event_handler.systemzones", true)
      cbus_SetState(CBUS_APP, CBUS_ZONE_GROUPS[zoneIndex], acZoneOn)
    end		    
  end
  
end


-- Global Event Handler
-- Create an event script that contains a single line to call this function.
-- Associate it with a keyword such as "izone_event" and add this keyword to all the relevant groups:
--   CBUS_SYSTEMON_GROUP
--   CBUS_MODE_GROUP
--   CBUS_FAN_GROUP
--   CBUS_ZONE_GROUPS[]
--   CBUS_USERPARAM_NAME_SETPOINT

function P.Event_Handler()

  -- event.sender is either "us" (sent over bus) or "sr" (sent from within the script)
  if ( event.sender ~= "us" ) then
    -- if we triggered this from within user.izone then don't process it as an intentional change
    if ( storage.get("izone.disable_event_handler", false) == true ) then
      return
    end
  end
  
-- log( tostring2( event) )

--  local cbus = P.GetCbusSystemSettings()
  
  if ( GroupAddressMatches( event.dst, 0, CBUS_APP, CBUS_SYSTEMON_GROUP ) ) then
    if ( storage.get("izone.disable_event_handler.systemon") == true ) then
      storage.delete("izone.disable_event_handler.systemon")
      return
    else
      local cbusSystemOn = GetCBusState(0, CBUS_APP, CBUS_SYSTEMON_GROUP)
      if ( cbusSystemOn == true ) then
        log("Executing action: Airconditioner on")
        P.Post("SystemON", '{"SystemON":"on"}', IZONE_POST_ATTEMPTS)
      else
        log("Executing action: Airconditioner off")
        P.Post("SystemON", '{"SystemON":"off"}', IZONE_POST_ATTEMPTS)
      end
    end
  elseif ( GroupAddressMatches( event.dst, 0, CBUS_APP, CBUS_MODE_GROUP ) ) then
    if ( storage.get("izone.disable_event_handler.systemmode") == true ) then
      storage.delete("izone.disable_event_handler.systemmode")
      return
    else
      local cbusModeLevel = GetCBusLevel(0, CBUS_APP, CBUS_MODE_GROUP)
      local cbusMode = P.LevelToMode(cbusModeLevel)
      log("Executing action: Mode '" .. tostring(cbusMode) .. "'.")
      P.Post("SystemMODE", '{"SystemMODE":"' .. cbusMode .. '"}', IZONE_POST_ATTEMPTS)
    end
  elseif ( GroupAddressMatches( event.dst, 0, CBUS_APP, CBUS_FAN_GROUP ) ) then
    if ( storage.get("izone.disable_event_handler.systemfan") == true ) then
      storage.delete("izone.disable_event_handler.systemfan")
      return
    else
      local cbusFanLevel = GetCBusLevel(0, CBUS_APP, CBUS_FAN_GROUP)
      local cbusFan = AC_FAN_NAMES_POST[cbusFanLevel + 1]
      log("Executing action: Fan '" .. tostring(cbusFan) .. "'.")
      P.Post("SystemFAN", '{"SystemFAN":"' .. cbusFan .. '"}', IZONE_POST_ATTEMPTS)
    end
  elseif ( event.dst == CBUS_USERPARAM_GA_SETPOINT ) then
    if ( storage.get("izone.disable_event_handler.setpoint") == true ) then
      storage.delete("izone.disable_event_handler.setpoint")
      return
    else
      local cbusSetpoint = GetUserParam(0, CBUS_USERPARAM_NAME_SETPOINT)
      log("Executing action: Setpoint '" .. tostring(cbusSetpoint) .. "'.")
      P.Post("UnitSetpoint", '{"UnitSetpoint":"' .. cbusSetpoint .. '"}', IZONE_POST_ATTEMPTS)
    end
  else
	  for zoneIndex = 1,IZONE_ZONES,1 
    do
      if ( GroupAddressMatches( event.dst, 0, CBUS_APP, CBUS_ZONE_GROUPS[zoneIndex] ) ) then
        if ( storage.get("izone.disable_event_handler.systemzones") == true ) then
          storage.delete("izone.disable_event_handler.systemzones")
          return
        else
          local cbusZoneOn = GetCBusState(0, CBUS_APP, CBUS_ZONE_GROUPS[zoneIndex])
          if ( cbusZoneOn == true ) then
            log("Executing action: Zone " .. zoneIndex .. " on.")
            local body = '{"ZoneCommand":{"ZoneNo":"' .. zoneIndex .. '","Command":"open"}}'
            P.Post("ZoneCommand", body, IZONE_POST_ATTEMPTS)
          else
            log("Executing action: Zone " .. zoneIndex .. " off.")
            local body = '{"ZoneCommand":{"ZoneNo":"' .. zoneIndex .. '","Command":"close"}}'
            P.Post("ZoneCommand", body, IZONE_POST_ATTEMPTS)
          end
        end
        do return end        
      end
    end
    
	  log("Could not determine action.")
  end
end

  
-- return the library
return P

