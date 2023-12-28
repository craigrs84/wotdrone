wotdrone.BaseController = wotdrone.BaseController or {}
local BaseController = wotdrone.BaseController
local success = "success"

local _promptRex = rex.new("^(([o*])(?: ([RSF]))? HP:(\\w+)(?: [SD]P:(\\w+))? MV:(\\w+)(?: - (.+?): (\\w+))? > )+(.*)$")

function BaseController:initialize()
  BaseController._lock = true
  self._shortLimit = 10
  self._longLimit = 20
  self._extendedLimit = 100
  self._packet = ""
  self._triggerIds = {}
  self._timerIds = {}
  self._deferredActions = {}
  self._dark = false
  self._riding = false
  self._sneaking = false
  self._flying = false
  self._hps = nil
  self._sps = nil
  self._mvs = nil
  self._enemyName = nil
  self._enemyHps = nil

  --add line/packet trigger
  self:addTrigger(self:createLineTrigger())

  --add heartbeat timer
  self:addTimer(self:createHeartbeatTimer())

  --create the coroutine
  self._co = coroutine.create(function()
    self:worker()
  end)
end

function BaseController:start()
  --test if already running
  if BaseController._lock then
    error("<red>Error: Bot is already running.\n")
  end

  cecho("<green>Bot started.\n")

  --intitialize
  self:initialize()

  --start the coroutine
  self:dispatch("start")
end

function BaseController:stop()
  --test if already running
  if not BaseController._lock then
    error("<red>Error: Bot is not running.\n")
  end
  
  --stop the coroutine
  self:dispatch("stop")
end

function BaseController:finalize()
  --remove all triggers
  for id, _ in pairs(self._triggerIds) do
    self:removeTrigger(id)
  end

  --remove all timers
  for id, _ in pairs(self._timerIds) do
    self:removeTimer(id)
  end

  BaseController._lock = nil

  cecho("<green>Bot finished.\n")
end

function BaseController:dispatch(...)
  --dispatch the event/action
  if self._co == nil then
    return
  end
  
  if coroutine.status(self._co) ~= "suspended" then
    return
  end

  local results = {coroutine.resume(self._co, ...)}
  if coroutine.status(self._co) == "dead" then
    self:finalize()
  end

  assert(unpack(results))
end

function BaseController:addTrigger(id)
  self._triggerIds[id] = true
  return id
end

function BaseController:removeTrigger(id)
  self._triggerIds[id] = nil
  disableTrigger(id)
  killTrigger(id)
end

function BaseController:addTimer(id)
  self._timerIds[id] = true
  return id
end

function BaseController:removeTimer(id)
  self._timerIds[id] = nil
  disableTimer(id)
  killTimer(id)
end

function BaseController:addDeferredAction(action)
  table.insert(self._deferredActions, action)
end

function BaseController:runDeferredActions()
  for index, action in ipairs(self._deferredActions) do
    self._deferredActions[index] = nil
    action()
  end
end

function BaseController:createLineTrigger()
  return tempRegexTrigger(f"^.*$", function()
    self._lastLine = line
    self:dispatch("wotmudLine", line)

    local prompt, trailing = self:isPrompt(line)
    if prompt ~= nil then
      --prompt
      self._packet = self._packet .. prompt .. "\n"        
      self._lastPacket = self._packet
      self:dispatch("wotmudPacket", self._packet)        
      self._packet = trailing:len() > 0 and trailing .. "\n" or ""
    else
      --not prompt
      self._packet = self._packet .. line .. "\n"
    end
  end)
end

function BaseController:createHeartbeatTimer()
  return tempTimer(1, function()
    self:dispatch("heartbeat")
  end, true)
end

function BaseController:isPrompt(line)
  local prompt, dark, action, hps, sps, mvs, enemyName, enemyHps, trailing = _promptRex:match(line)
  if prompt ~= nil then
    self._dark = dark == "o"
    self._riding = action == "R"
    self._sneaking = action == "S"
    self._flying = action == "F"
    self._hps = hps
    self._sps = sps or nil
    self._mvs = mvs
    self._enemyName = enemyName or nil
    self._enemyHps = enemyHps or nil
    return prompt, trailing
  end
  return nil
end

function BaseController:intercept(code, ...)
  if code == "wotmudPacket" then
    self:interceptPacket(...)
  end
end

function BaseController:interceptPacket(...)
  --todo: override this method in subclass
end

function BaseController:worker()
  error("not implemented")
end

function BaseController:readLineAsync()
  while true do
    local results = {coroutine.yield()}
    self:intercept(unpack(results))

    local code = results[1]
    if code == "stop" then
      error("stop")
    end

    if code == "wotmudLine" then
      return results[2]
    end
  end
end

function BaseController:readPacketAsync()
  while true do
    local results = {coroutine.yield()}
    self:intercept(unpack(results))
    
    local code = results[1]
    if code == "stop" then
      error("stop")
    end

    if code == "wotmudPacket" then
      return results[2]
    end
  end
end

function BaseController:waitAsync(time)
  local timerId
  timerId = self:addTimer(tempTimer(time, function()
    self:removeTimer(timerId)
    self:dispatch("waitCompleted")
  end))
  
  while true do
    local results = {coroutine.yield()}
    self:intercept(unpack(results))

    local code = results[1]
    if code == "stop" then
      error("stop")
    end

    self:runDeferredActions()
    if code == "waitCompleted" then
      return
    end
  end
end

function BaseController:basicAction(command, args, patterns, limit)
  local results = {}

  limit = limit or self._shortLimit
  if not table.is_empty(args) then
    command = command .. " " .. table.concat(args, " ")
  end

  send(command)
  for i = 1, limit do
    local packet = self:readPacketAsync()

    for key, value in pairs(patterns) do
      local matches = {rex.match(packet, value, 1, "m")}
      if not table.is_empty(matches) then
        results[key] = matches
      end
    end

    if not table.is_empty(results) then
      self:runDeferredActions()
      return results, packet
    end
  end
  
  error("error during: " .. command)
end

--basic action: look
function BaseController:look(...)
  return self:basicAction("look", {...}, {
    success = "^\\[ obvious exits: .* \\]$",
    dark = "^It is pitch black\\.\\.\\.$"
  })
end

--basic action: move
function BaseController:move(direction, ...)
  return self:basicAction(direction, {...}, {
    success = "^\\[ obvious exits: .* \\]$",
    dark = "^It is pitch black\\.\\.\\.$",
    invalid = "^Alas, you cannot go that way\\.\\.\\.$",
    closedGate = "^The \\w*[Gg]ate\\w* seems to be closed\\.$",
    closedDoor = "^.+ seems to be closed\\.$",
    exhausted = "^You are too exhausted\\.$",
    mountExhausted = "^Your mount is too exhausted\\.$",
    engaged = "^No way!  You're fighting for your life!$"
  })
end

--basic action: flee
function BaseController:flee(...)
  return self:basicAction("flee", {...}, {
    success = "^\\[ obvious exits: .* \\]$",
    dark = "^It is pitch black\\.\\.\\.$",
    fail = "^PANIC!  You couldn't escape!$",
    mounted = "^You can't ride in there\\.$",
    exhausted = "^You are too exhausted\\.$",
    mountExhausted = "^Your mount is too exhausted\\.$"
  })
end

function BaseController:kill(target, name)
  return self:basicAction("kill", {target}, {
    success = "^" .. name .. " is dead!  R\\.I\\.P\\.$",
    notHere = "^They aren't here\\.$"
  }, self._extendedLimit)
end

function BaseController:call(...)
  return self:basicAction("call", {...}, {
    success = "^You call for .+ to be opened\\.\\n.+ is opened from the other side\\.$"
  })
end

function BaseController:openDoor(...)
  return self:basicAction("open door", {...}, {
    success = "^Ok.$|^It's already open!$",
    noDoor = "^I see no .+ here\\.$",
    locked = "^It seems to be locked\\.$"
  })
end

--basic action: dismount
function BaseController:dismount(...)
  return self:basicAction("dismount", {...}, {
    success = "^You stop riding .+\\.$",
    notRiding = "^But you're not riding anything!$"
  })
end

--basic action: stat
function BaseController:stat(...)
  return self:basicAction("stat", {...}, {
    success = "^You are a .+ (?:male|female) .+\\.",
  })
end

--basic action: stat
function BaseController:equipment(...)
  return self:basicAction("equipment", {...}, {
    success = "^You are using:$",
  })
end


--composite action: look with retry
function BaseController:lookWithRetry()
  for i = 1, self._shortLimit do
    local keys = table.keys(self:look())
    if table.index_of(keys, success) then
      return success
    end
    self:waitAsync(60)
  end
  error("error during: lookWithRetry")
end

--composite action: flee with retry
function BaseController:fleeWithRetry()
  for i = 1, self._shortLimit do
    local keys = table.keys(self:flee())
    if table.index_of(keys, success) then
      return success
    end
  end
  error("error during: fleeWithRetry")
end

--composite action: moveTo
function BaseController:moveTo(roomId, delay, limit)
  delay = delay or 0
  limit = limit or 9999
  
  if getPlayerRoom() == roomId then
    return success
  end
  
  local retries = 0
  while retries < 500 do

    local path = nil
    if getPath(getPlayerRoom(), roomId) then
      path = speedWalkDir
    end

    if not path then
      error("cannot move to that room.")
    end
    
    local direction = path[1]
    local door = getRoomUserData(getPlayerRoom(), direction)
    if door and door ~= "" then
      self:openDoor(direction)
    end
    
    local keys = table.keys(self:move(direction))
    if getPlayerRoom() == roomId then
      return success
    elseif table.index_of(keys, "engaged") then
      self:fleeWithRetry()
    elseif table.index_of(keys, "closedGate") then
      self:call()
    elseif table.index_of(keys, "closedDoor") then
      self:openDoor(direction)
    elseif table.index_of(keys, "exhausted") or table.index_of(keys, "mountExhausted") then
      self:waitAsync(10)
    elseif delay then
      self:waitAsync(delay)
    end
    
    if getPlayerRoom() == roomId then
      return success
    end
  end

  error("error during: moveTo")
end
