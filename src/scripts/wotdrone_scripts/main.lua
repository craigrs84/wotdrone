wotdrone = wotdrone or {}

local _envTypes = {
  armorer = 28,
  bank = 30,
  blacksmith = 29,
  city = 38,
  drink = 26,
  grocer = 33,
  herb = 39,
  herbalist = 45,
  horse = 23,
  hunter = 36,
  inside = 20,
  nochannel = 41,
  pk = 37,
  portalstone = 42,
  rent = 32,
  road = 22,
  rogue = 35,
  smob = 44,
  stables = 31,
  swamp = 24,
  tailor = 40,
  trees = 43,
  warrior = 34,
  water = 25,
  weaponsmith = 27,
  wilderness = 21
}

tempTimer(1, function()
  for roomId, _ in pairs(getRooms()) do
    local env = getRoomEnv(roomId)
    local zone = getRoomUserData(roomId, "zone")    
    
    --City / Road
    if env == _envTypes.city or
      env == _envTypes.road then
      setRoomWeight(roomId, 1)
    
    --Wilderness / Swamp
    elseif env == _envTypes.wilderness or
      env == _envTypes.swamp then
      setRoomWeight(roomId, 5)
      
    --Inside
    elseif env == _envTypes.inside or
      env == _envTypes.armorer or 
      env == _envTypes.bank or
      env == _envTypes.blacksmith or
      env == _envTypes.grocer or
      env == _envTypes.herbalist or
      env == _envTypes.rent or
      env == _envTypes.tailor or
      env == _envTypes.weaponsmith then
      setRoomWeight(roomId, 25)
    
    --Water
    elseif env == _envTypes.water then
      setRoomWeight(roomId, 50)
    end

    --Waterless Sands Zone
    if zone == "The Waterless Sands" then
      setRoomWeight(roomId, getRoomWeight(roomId) + 10)
    end
  end
  
  cecho("\n<orange>Updated room weights.\n")
end)
