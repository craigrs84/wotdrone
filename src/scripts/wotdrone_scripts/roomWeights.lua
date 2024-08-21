wotdrone = wotdrone or {}
wotdrone.RoomWeights = wotdrone.RoomWeights or {}
local RoomWeights = wotdrone.RoomWeights
local EnvTypes = wotdrone.Globals.EnvTypes

function RoomWeights:initialize()
  for roomId, _ in pairs(getRooms()) do
    local weight = 1
    
    local env = getRoomEnv(roomId)
    if env == EnvTypes.swamp then
      weight = 3 --Swamp
    elseif env == EnvTypes.wilderness then
      weight = 5 --Wilderness
    elseif env == EnvTypes.inside or
      env == EnvTypes.armorer or 
      env == EnvTypes.bank or
      env == EnvTypes.blacksmith or
      env == EnvTypes.grocer or
      env == EnvTypes.herbalist or
      env == EnvTypes.rent or
      env == EnvTypes.tailor or
      env == EnvTypes.weaponsmith or
      env == EnvTypes.smob then
      weight = 25 --Inside
    elseif env == EnvTypes.water then
      weight = 50 --Water
    end

    local zone = getRoomUserData(roomId, "zone")
    if zone == "The Waterless Sands" then
      weight = weight + 10 --Waterless Sands Zone
    end

    setRoomWeight(roomId, weight)
  end
  
  cecho("\n<orange>Updated room weights.\n")
end