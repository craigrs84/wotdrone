wotdrone = wotdrone or {}
wotdrone.Controller = wotdrone.Controller or {}
local Controller = wotdrone.Controller

function Controller:doStep(roomId, reject)
  local limit = 15
  local tries = 0
  reject = reject or error

  while true do
    --calc direction
    if getPlayerRoom() == roomId then
      return
    end
    if not getPath(getPlayerRoom(), roomId) then
      error("impossible-path")
    end
    local direction = speedWalkDir[1]

    --move
    local code = self:move(direction)

    --success
    if table.index_of({"ok", "dark", "blind"}, code) then
      return
    end
    
    --retry
    tries = tries + 1
    if tries >= limit then
      error("max-failures-exceeded")
    end

    if code == "fail-closed-door" then
      self:doOpenDoor(direction)
    elseif code == "fail-mounted" then
      self:doLead()
    elseif table.index_of({"fail-engaged", "fail-mount-engaged"}, code) then
      self:doFlee()
    elseif table.index_of({"fail-exhausted", "fail-mount-exhausted"}, code) then
      self:waitForTimer(10)
    end
  end  
end

function Controller:doWalk(roomId)
  while getPlayerRoom() ~= roomId do
    self:doStep(roomId)
  end
end

function Controller:openDoor(direction)
  send("open door " .. direction)
  return self:waitForPacket({
    {true, "ok", "^Ok\\.$"},
    {true, "already-open", "^It's already open!$"},
    {true, "fail-no-door", "^I see no .+ t?here\\.$"},
    {false, "fail-no-door", "^That's impossible, I'm afraid\\.$"},
    {false, "fail-locked-door", "^It seems to be locked\\.$"}
  })
end

function Controller:doOpenDoor2(direction, throw)
  local code = self:openDoor(direction)

  if code == "fail-locked" then
    
  else
    self:assert(code)
  end
end

function Controller:doOpenDoor(direction, throw)
  throw = throw == nil and true
  local resolve = function(x) return true, x or "success" end
  local reject = throw and function(x) error("fail: " .. x) end or function(x) return false, x or "error" end
  local code = self:openDoor(direction)

  --open-success
  if table.index_of({"ok", "already-open", "fail-no-door"}, code) then
    return resolve()
  end

  --locked
  if code == "fail-locked-door" then
    code = self:callDoor(direction)

    --call-success
    if table.index_of({"ok", "already-open", "fail-no-door"}, code) then
      return resolve()
    end
  end

  return reject("cannot-open-door")
end

function Controller:doLead(target)
  local limit = 15
  local tries = 0

  while true do
    local code = self:lead(target)
    
    --success
    if table.index_of({"ok", "already-leading"}, code) then
      return
    end
    
    --error
    if table.index_of({"fail-unknown-mount", "fail-missing-mount", "fail-too-many"}, code) then
      error(code)
    end

    --retry
    tries = tries + 1
    if tries >= limit then
      error("max-failures-exceeded")
    end

    if code == "fail-sitting" then
      send("stand")
    elseif code == "fail-resting" then
      send("stand")
    elseif code == "fail-sleeping" then
      sendAll("wake", "stand")
    elseif code == "fail-mounted" then
      send("dismount")
    end
  end
end

function Controller:doFlee()
  local limit = 15
  local tries = 0

  while true do
    local code = self:flee()

    --success
    if table.index_of({"ok", "dark", "blind"}, code) then
      return
    end 

    --error
    if code == "fail-berserk" then
      error(code)
    end

    --retry
    tries = tries + 1
    if tries >= limit then
      error("max-failures-exceeded")
    end

    if code == "fail-sitting" then
      send("stand")
    elseif code == "fail-resting" then
      send("stand")
    elseif code == "fail-sleeping" then
      sendAll("wake", "stand")
    end
  end
end