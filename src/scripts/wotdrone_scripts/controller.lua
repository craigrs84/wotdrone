wotdrone = wotdrone or {}
wotdrone.Controller = wotdrone.Controller or {}
local Controller = wotdrone.Controller

Controller.depth = Controller.depth or 0

function Controller:intercept(code, payload)
  if code == "packet" then
    local packet = payload.packet

    if self:isMatch(packet, "^You are hungry\\.$") then
      local code = self:eat("meat")
      if self:isFail(code) then
        self:eat("food")
      end
    end
    
    if self:isMatch(packet, "^You are thirsty\\.$") then
      self:drink("skin")
    end
  end
end

function Controller:waitForEvent(options)
  local co = coroutine.running()
  local active = true
  local fired = false
  local packets = {}
  local tempTimerId
  local intervalId
  local timerId
  local aggroHandlerId
  local ticHandlerId
  local packetHandlerId

  --kill
  local killAll = function()
    killTimer(tempTimerId or 0)
    killTimer(intervalId or 0)
    killTimer(timerId or 0)
    killAnonymousEventHandler(aggroHandlerId or 0)
    killAnonymousEventHandler(ticHandlerId or 0)
    killAnonymousEventHandler(packetHandlerId or 0)
  end

  tempTimerId = tempTimer(0, function()
    if coroutine.status(co) == "dead" then
      killAll()
      return
    end
    
    --interval
    intervalId = tempTimer(1, function()
      if coroutine.status(co) == "dead" then
        killAll()
        return
      end

      if options.type == "interval" then
        fired = true
      end

      if active then
        assert(coroutine.resume(co, "interval"))
      end
    end, true)

    --timer
    if options.type == "timer" then
      timerId = tempTimer(options.time, function()
        if coroutine.status(co) == "dead" then
          killAll()
          return
        end

        fired = true

        if active then
          assert(coroutine.resume(co, "timer"))
        end
      end)
    end

    --aggro
    aggroHandlerId = registerAnonymousEventHandler("aggro_pulse", function(event)
      if coroutine.status(co) == "dead" then
        killAll()
        return
      end

      if options.type == "aggro" then
        fired = true
      end

      if active then
        assert(coroutine.resume(co, "aggro"))
      end
    end)

    --tic
    ticHandlerId = registerAnonymousEventHandler("tic", function(event)
      if coroutine.status(co) == "dead" then
        killAll()
        return
      end

      if options.type == "tic" then
        fired = true
      end

      if active then
        assert(coroutine.resume(co, "tic"))
      end
    end)
  
    --packet
    packetHandlerId = registerAnonymousEventHandler("wotmudPacket", function(event, packet)
      if coroutine.status(co) == "dead" then
        killAll()
        return
      end

      if options.type == "packet" then
        fired = true
        table.insert(packets, packet)
      end

      if active then
        assert(coroutine.resume(co, "packet", {packet = packet, packets = packets}))
      end
    end)
  end)

  --loop
  while true do
    active = true
    local code, payload = coroutine.yield()
    active = false

    if code == "abort" then
      killAll()
      error("Aborted")
    end

    if self.depth < 15 then
      self.depth = self.depth + 1
      self:intercept(code, payload)
      self.depth = self.depth - 1
    end

    if fired then
      killAll()
      return code, payload
    end
  end
end

function Controller:waitForTimer(time)
  self:waitForEvent({type = "timer", time = time})
end

function Controller:waitForAggro()
  self:waitForEvent({type = "aggro"})
end

function Controller:waitForTic()
  self:waitForEvent({type = "tic"})
end

function Controller:nextPackets()
  local _, payload = self:waitForEvent({type = "packet"})
  return payload.packets
end

function Controller:waitForPacket(filter, limit)
  local count = 0
  limit = limit or 15

  while true do
    local packets = self:nextPackets()
    for _, packet in ipairs(packets) do
      local key, matches = self:isMatch(packet, filter)
      if key ~= nil then
        return key, packet, matches
      end
      count = count + 1
      if count >= limit then
        error("Matching packet not found")  
      end
    end
  end
end

function Controller:isMatch(packet, filter)
  if type(filter) == "string" then
    local key = "ok"
    local pattern = filter
    local matches = {rex.match(packet, pattern, 1, "m")}
    if matches[1] ~= nil then
      return key, matches
    end
  elseif type(filter) == "table" then
    for _, entry in ipairs(filter) do
      local key = entry[1]
      local pattern = entry[2]
      local matches = {rex.match(packet, pattern, 1, "m")}
      if matches[1] ~= nil then
        return key, matches
      end
    end
  elseif type(filter) == "function" then
    local key, matches = filter(packet)
    if key ~= nil then
      return key, matches
    end
  end
  return nil
end

function Controller:isFail(code)
  return code:match("^fail.*") ~= nil
end

function Controller:look()
  send("look")
  return self:waitForPacket({
    {"ok", "^[\\s\\S]+^\\[ obvious exits: .* \\]$"},
    {"dark", "^It is pitch black\\.\\.\\.$"},
    {"blind", "^You can't see a damned thing, you're blinded!$"}
  })
end

function Controller:score()
  send("score")
  return self:waitForPacket({
    {"ok", "^You have \\d+\\(\\d+\\) hit"}
  })
end

function Controller:eat(target)
  send("eat " .. target)
  return self:waitForPacket({
    {"ok", "^You eat (.+)\\.$"},
    {"not-hungry", "^You are too full to eat more!$"},
    {"fail-missing", "^You don't seem to have any\\.$"}
  })
end

function Controller:drink(target)
  send("drink " .. target)
  return self:waitForPacket({
    {"ok", "^You drink (.+)\\.\\nYou don't feel thirsty any more\\.$"},
    {"ok", "^You drink (.+)\\.$"},
    {"not-thirsty", "^You're not thirsty\\.$"},
    {"fail-missing", "^You can't find it!$"},
    {"fail-empty", "^It's empty\\.$"}
  })
end

function Controller:openDoor(direction)
  send("open door " .. direction)
  return self:waitForPacket({
    {"ok", "^Ok\\.$"},
    {"already-open", "^It's already open!$"},
    {"fail-no-door", "^I see no .+ t?here\\.$"},
    {"fail-no-door", "^That's impossible, I'm afraid\\.$"},
    {"fail-locked-door", "^It seems to be locked\\.$"}
  })
end

function Controller:callDoor(direction)
  send("call " .. direction)
  return self:waitForPacket({
    {"ok", "^You call for .+ to be opened\\.$[\\s\\S]*^.+ opens .+\\.$"},
    {"ok", "^You call for .+ to be opened\\.$[\\s\\S]*^.+ is opened from the other side\\.$"},
    {"already-open", "^You call for .+ to be opened\\.$[\\s\\S]*^.+ points to the obviously open .+\\.$"},
    {"fail-no-door", "^You don't see a closed gate.\\.$"},
    {"fail-no-response", "^You call for .+ to be opened\\.$"}
  })
end

function Controller:move(direction)
  send(direction)
  return self:waitForPacket({
    {"ok", "^[\\s\\S]+^\\[ obvious exits: .* \\]$"},
    {"dark", "^It is pitch black\\.\\.\\.$"},
    {"blind", "^You can't see a damned thing, you're blinded!$"},
    {"fail-invalid", "^Alas, you cannot go that way\\.\\.\\.$"},
    {"fail-engaged", "^No way!  You're fighting for your life!$" },
    {"fail-sitting", "^Maybe you should get on your feet first\\?$"},
    {"fail-resting", "^Nah\\.\\.\\. You feel too relaxed to do that\\.\\.$"},
    {"fail-sleeping", "^In your dreams, or what\\?$"},
    {"fail-frozen", "^You try, but the mind-numbing cold prevents you\\.\\.$"},
    {"fail-stunned", "^All you can do right now is think about the stars!$"},
    {"fail-incapacitated", "^You're in pretty bad shape, unable to do anything!$"},
    {"fail-water", "^You would need to swim there, you can't just walk it\\.$"},
    {"fail-water", "^You shudder at the concept of crossing water\\.$"},
    {"fail-mounted-water", "^You can't ride on water\\.$"},
    {"fail-mounted", "^You can't ride in there\\.$"},
    {"fail-mounted", "^You can't ride there on a horse!$"},
    {"fail-exhausted", "^You are too exhausted\\."},
    {"fail-mount-exhausted", "^Your mount is too exhausted\\."},
    {"fail-mount-engaged", "^Your mount is engaged in combat!$"},
    {"fail-mount-disobeyed", "Your mount refuses to obey your command\\.$"},
    {"fail-mount-slacking", "^Your mount ought to be awake and standing first!$"},
    --{"fail-closed-gate", "^(?:The|An?) \\w*[Gg]ate\\w* seems to be closed\\.$"},
    {"fail-closed-door", "^.+ seems to be closed\\.$"},
    {"fail-blocked", "^(.+) blocks the way\\.$"},
    {"fail-blocked", "^(.+) blocks your path\\.$"}
   })
end

function Controller:flee()
  send("flee")
  return self:waitForPacket({
    {"ok", "^[\\s\\S]+^\\[ obvious exits: .* \\]$"},
    {"dark", "^It is pitch black\\.\\.\\.$"},
    {"blind", "^You can't see a damned thing, you're blinded!$"},
    {"fail-berserk", "^Berserk! Death! Death! Fight to the death!$"},
    {"fail-panic", "^PANIC!  You couldn't escape!$"},
    {"fail-fear", "^PANIC!  Fear paralyzes you!$"},
    {"fail-sitting", "^Maybe you should get on your feet first\\?$"},
    {"fail-resting", "^Nah\\.\\.\\. You feel too relaxed to do that\\.\\.$"},
    {"fail-sleeping", "^In your dreams, or what\\?$"},
    {"fail-frozen", "^You try, but the mind-numbing cold prevents you\\.\\.$"},
    {"fail-stunned", "^All you can do right now is think about the stars!$"},
    {"fail-incapacitated", "^You're in pretty bad shape, unable to do anything!$"},
    {"fail-mounted", "^You can't ride in there\\.$"},
    {"fail-mounted", "^You can't ride there on a horse!$"},
    {"fail-exhausted", "^You are too exhausted\\."},
    {"fail-mount-exhausted", "^Your mount is too exhausted\\."},
    {"fail-mount-engaged", "^Your mount is engaged in combat!$"},
    {"fail-mount-slacking", "^Your mount ought to be awake and standing first!$"},
    {"fail-closed-door", "^(.+) is closed\\.$"},
    {"fail-blocked", "^(.+) blocks the way\\.$"},
    {"fail-blocked", "^(.+) blocks your path\\.$"}
   })
end

function Controller:lead(target)
  send("lead " .. (target or ""))
  return self:waitForPacket({
    {"ok", "^.+ starts following you\\.$"},
    {"already-leading", "^You're already leading it!$"},
    {"fail-too-many", "^You can't control that many at once!$"},
    {"fail-mounted", "^You must dismount before leading it!$"},
    {"fail-indifferent", "^.+ has an indifferent look\\.$"},
    {"fail-unknown-mount", "^What animal do you want to lead\\?$"},
    {"fail-missing-mount", "^They're not here to be led.$"},
    {"fail-sitting", "^Maybe you should get on your feet first\\?$"},
    {"fail-resting", "^Nah\\.\\.\\. You feel too relaxed to do that\\.\\.$"},
    {"fail-sleeping", "^In your dreams, or what\\?$"},
    {"fail-frozen", "^You try, but the mind-numbing cold prevents you\\.\\.$"},
    {"fail-stunned", "^All you can do right now is think about the stars!$"},
    {"fail-incapacitated", "^You're in pretty bad shape, unable to do anything!$"}
   })
end