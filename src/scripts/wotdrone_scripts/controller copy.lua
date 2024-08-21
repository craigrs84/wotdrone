wotdrone = wotdrone or {}
wotdrone.Controller = wotdrone.Controller or {}
local Controller = wotdrone.Controller

Controller.depth = Controller.depth or 0

function Controller:intercept(code, args)
  if code == "wotmudPacket" then
    local packet = args[1]

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

function Controller:waitForTimer(time)
  local co = coroutine.running()

  local active = true
  local fired = false

  local timerId
  timerId = tempTimer(time, function()
    fired = true
    if active then
      assert(coroutine.resume(co, "timer"))
    end
  end)

  local aggroHandlerId
  local aggroTimerId = tempTimer(0, function()
    aggroHandlerId = registerAnonymousEventHandler("aggro_pulse", function(event, packet)
      if active then
        assert(coroutine.resume(co, event, packet))
      end
    end)
  end)

  local ticHandlerId
  local ticTimerId = tempTimer(0, function()
    ticHandlerId = registerAnonymousEventHandler("tic", function(event, packet)
      if active then
        assert(coroutine.resume(co, event, packet))
      end
    end)
  end)

  local packetHandlerId
  local packetTimerId = tempTimer(0, function()
    packetHandlerId = registerAnonymousEventHandler("wotmudPacket", function(event, packet)
      if active then
        assert(coroutine.resume(co, event, packet))
      end
    end)
  end)

  local killAll = function()
    killTimer(timerId or 0)
    killTimer(aggroTimerId or 0)
    killAnonymousEventHandler(aggroHandlerId or 0)
    killTimer(ticTimerId or 0)
    killAnonymousEventHandler(ticHandlerId or 0)
    killTimer(packetTimerId or 0)
    killAnonymousEventHandler(packetHandlerId or 0)
  end

  while true do
    active = true
    local data = {coroutine.yield()}
    active = false

    if data[1] == "abort" then
      killAll()
      error("Aborted")
    end

    if self.depth < 15 then
      self.depth = self.depth + 1
      self:intercept(data[1], {unpack(data, 2)})
      self.depth = self.depth - 1
    end

    if fired then
      killAll()
      return
    end
  end
end


function Controller:waitForEvent(options)
  local co = coroutine.running()
  local active = true
  local fired = false
  local packets = {}
  local timerId
  local aggroTimerId
  local aggroHandlerId
  local ticTimerId
  local ticHandlerId
  local packetTimerId
  local packetHandlerId
  local intervalId
    
  local killAll = function()
    killTimer(timerId or 0)
    killTimer(aggroTimerId or 0)
    killAnonymousEventHandler(aggroHandlerId or 0)
    killTimer(ticTimerId or 0)
    killAnonymousEventHandler(ticHandlerId or 0)
    killTimer(packetTimerId or 0)
    killAnonymousEventHandler(packetHandlerId or 0)
    killTimer(intervalId or 0)
  end

  if options.type == "timer" then
    timerId = tempTimer(options.time, function()
      fired = true
      if active then
        assert(coroutine.resume(co, "timer"))
      end
    end)
  end

  aggroTimerId = tempTimer(0, function()
    aggroHandlerId = registerAnonymousEventHandler("aggro_pulse", function(event)
      fired = fired or options.type == "aggro"
      if active then
        assert(coroutine.resume(co, event))
      end
    end)
  end)

  ticTimerId = tempTimer(0, function()
    ticHandlerId = registerAnonymousEventHandler("tic", function(event, packet)
      if coroutine.status(co) == "dead" then
        --killAll()
        return
      end

      if options.type == "tic" then
        fired = true
      end

      if active then
        assert(coroutine.resume(co, event))
      end
    end)
  end)
 
  packetTimerId = tempTimer(0, function()
    packetHandlerId = registerAnonymousEventHandler("wotmudPacket", function(event, packet)
      if coroutine.status(co) == "dead" then
        killAll()
        return
      end

      if options.type == "wotmudPacket" then
        fired = true
        table.insert(packets, packet)
      end

      if active then
        assert(coroutine.resume(co, event, {packet = packet, packets = packets}))
      end
    end)
  end)

  intervalId = tempTimer(1, function()
    if coroutine.status(co) == "dead" then
      killAll()
      return
    end

    fired = fired or options.type == "interval"
    if active then
      assert(coroutine.resume(co, "timer"))
    end
  end, true)

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

function Controller:nextPackets()
  local co = coroutine.running()
  
  local active = true
  local fired = false
  local packets = {}

  local packetHandlerId
  local packetTimerId = tempTimer(0, function()
    packetHandlerId = registerAnonymousEventHandler("wotmudPacket", function(event, packet)
      fired = true
      table.insert(packets, packet)
      if active then
        assert(coroutine.resume(co, event, packet))
      end
    end)
  end)
 
  local killAll = function()
    killTimer(packetTimerId or 0)
    killAnonymousEventHandler(packetHandlerId or 0)
  end

  while true do
    active = true
    local data = {coroutine.yield()}
    active = false
    
    if data[1] == "abort" then
      killAll()
      error("Aborted")
    end

    if self.depth < 10 then
      self.depth = self.depth + 1
      self:intercept(data[1], {unpack(data, 2)})
      self.depth = self.depth - 1
    end
    
    if fired then
      killAll()
      return packets
    end
  end
end

function Controller:waitForPacket(criteria, limit)
  local count = 0
  limit = limit or 15

  while true do
    local packets = self:nextPackets()
    for _, packet in ipairs(packets) do
      local key, matches = self:isMatch(packet, criteria)
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

function Controller:isMatch(packet, criteria)
  if type(criteria) == "string" then
    local key = "ok"
    local pattern = criteria
    local matches = {rex.match(packet, pattern, 1, "m")}
    if matches[1] ~= nil then
      return key, matches
    end
  elseif type(criteria) == "table" then
    for _, entry in ipairs(criteria) do
      local key = entry[1]
      local pattern = entry[2]
      local matches = {rex.match(packet, pattern, 1, "m")}
      if matches[1] ~= nil then
        return key, matches
      end
    end
  elseif type(criteria) == "function" then
    local key, matches = criteria(packet)
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