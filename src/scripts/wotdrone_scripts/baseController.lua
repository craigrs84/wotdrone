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

function BaseController:waitForPacketAsync(patterns, limit)
  limit = limit or self._shortLimit
   
  for i = 1, limit do
    local packet = self:readPacketAsync()

    for _, pattern in pairs(patterns) do
      local matches = {rex.match(packet, pattern.text, 1, "m")}
      if not table.is_empty(matches) then
        return pattern.code, packet, matches
      end
    end
  end

  return nil
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
  if not table.is_empty(args) then
    command = command .. " " .. table.concat(args, " ")
  end

  send(command)
  local code, packet, matches = self:waitForPacketAsync(patterns, limit)
  if (code) then
    return code, packet, matches
  end
  
  error("error during: " .. command)
end

--basic action: look
function BaseController:look(...)
  return self:basicAction("look", {...}, {
    { code = "success", text = "^\\[ obvious exits: .* \\]$" },
    { code = "dark", text = "^It is pitch black\\.\\.\\.$" }
  })
end

--basic action: move
function BaseController:move(direction, ...)
  return self:basicAction(direction, {...}, {
    { code = "success", text = "^\\[ obvious exits: .* \\]$" },
    { code = "dark", text = "^It is pitch black\\.\\.\\.$" },
    { code = "invalid", text = "^Alas, you cannot go that way\\.\\.\\.$" },
    { code = "closedGate", text = "^The \\w*[Gg]ate\\w* seems to be closed\\.$" },
    { code = "closedDoor", text = "^.+ seems to be closed\\.$" },
    { code = "exhausted", text = "^You are too exhausted\\.$" },
    { code = "mountExhausted", text = "^Your mount is too exhausted\\.$" },
    { code = "engaged", text = "^No way!  You're fighting for your life!$" }
  })
end

--basic action: flee
function BaseController:flee(...)
  return self:basicAction("flee", {...}, {
    { code = "success", text = "^\\[ obvious exits: .* \\]$" },
    { code = "dark", text = "^It is pitch black\\.\\.\\.$" },
    { code = "fail", text = "^PANIC!  You couldn't escape!$" },
    { code = "mounted", text = "^You can't ride in there\\.$" },
    { code = "exhausted", text = "^You are too exhausted\\.$" },
    { code = "mountExhausted", text = "^Your mount is too exhausted\\.$" }
  })
end

function BaseController:kill(target, name)
  return self:basicAction("kill", {target}, {
    { code = "success", text = "^" .. name .. " is dead!  R\\.I\\.P\\.$" },
    { code = "notHere", text = "^They aren't here\\.$" }
  }, self._extendedLimit)
end

function BaseController:call(...)
  return self:basicAction("call", {...}, {
    { code = "success", text = "^You call for .+ to be opened\\.\\n.+ is opened from the other side\\.$" },
    { code = "success2", text = "^You call for .+ to be opened\\.$\\n[\\s\\S]*^.+ opens .+\\.$" },
    { code = "success3", text = "^You call for .+ to be opened\\.$" }
  })
end

function BaseController:openDoor(...)
  return self:basicAction("open door", {...}, {
    { code = "success", text = "^Ok.$|^It's already open!$" },
    { code = "noDoor", text = "^I see no .+ here\\.$" },
    { code = "locked", text = "^It seems to be locked\\.$" }
  })
end

--basic action: dismount
function BaseController:dismount(...)
  return self:basicAction("dismount", {...}, {
    { code = "success", text = "^You stop riding .+\\.$" },
    { code = "notRiding", text = "^But you're not riding anything!$" }
  })
end

--basic action: stat
function BaseController:stat(...)
  return self:basicAction("stat", {...}, {
    { code = "success", text = "^You are a .+ (?:male|female) .+\\." },
  })
end

--basic action: stat
function BaseController:equipment(...)
  return self:basicAction("equipment", {...}, {
    { code = "success", text = "^You are using:$" },
  })
end

--composite action: look with retry
function BaseController:lookWithRetry()
  for i = 1, self._shortLimit do
    if self:look() == "success" then
      return success
    end
    self:waitAsync(60)
  end
  error("error during: lookWithRetry")
end

--composite action: flee with retry
function BaseController:fleeWithRetry()
  for i = 1, self._shortLimit do
    if self:look() == "success" then
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
    
    local code = self:move(direction)
    if getPlayerRoom() == roomId then
      return success
    elseif code == "engaged" then
      self:fleeWithRetry()
    elseif code == "closedGate" then
      self:call()
    elseif code == "closedDoor" then
      self:openDoor(direction)
    elseif code == "exhausted" or code == "mountExhausted" then
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



-- create event callback queue
-- so for example timer fires (add that event to queue with timer id as state/arg)
-- for example packet received, add that even to queue
-- question how do we clear queue if nothing is listening to event, for example line received?



--example problem
-- main thread waits for delay
  --interrupt triggers a secondary wait
  -- main threads timer fires but is missed because were waiting on secondary thread/wait