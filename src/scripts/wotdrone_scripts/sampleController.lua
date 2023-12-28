wotdrone.SampleController = wotdrone.SampleController or setmetatable({}, { __index = wotdrone.BaseController })
local SampleController = wotdrone.SampleController

local success = "success"

function SampleController:interceptPacket(packet)
  if rex.match(packet, "^It is pitch black\\.\\.\\.$", 1, "m") or
    rex.match(packet, "^.+ has gone out!$", 1, "m") then
    send("hold lantern")
  end

  if rex.match(packet, "gold|copper", 1, "m") then
    send("get all.coin")
  end
  
  if rex.match(packet, "^You are hungry\\.$", 1, "m") then
    self.hungry = true
  end

  if rex.match(packet, "^You are thirsty\\.$", 1, "m") then
    self.thirsty = true
  end
end

function SampleController:worker()
  self._roomIds = {570, 571, 572, 574, 613, 612, 614, 617, 618, 619, 620, 621, 622, 617, 616, 615, 614, 612, 609, 610, 611, 623, 624, 625, 609, 608, 575, 576, 575, 570}
  self._roomIndex = 0

  while true do
    self:findSapling()

    while true do
      local keys = table.keys(self:killSapling())
      if table.index_of(keys, "level") then
        self:stat()
        local stats = {rex.match(self._lastPacket, "^Your base abilities are: Str:(\\d+) Int:(\\d+) Wil:(\\d+) Dex:(\\d+) Con:(\\d+)\\.$", 1, "m")}
        if not table.is_empty(stats) then
          local str, int, wil, dex, con = unpack(stats)
          str, int, wil, dex, con = tonumber(str), tonumber(int), tonumber(wil), tonumber(dex), tonumber(con)
          send("disengage")

          if str >= 19 and int >= 16 and wil >= 12 and dex >= 18 and con >= 19 then
            cecho("<green>Congratulations!\n")
            return
          end

          send("restat")
          self:waitAsync(3)
          self:equipment()
          if rex.match(self._lastPacket, "scratched|blunt") then
            self:replaceStaff()
            break
          end
        end
      elseif not table.index_of(keys, success) then
        break
      end
    end
  end
end

function SampleController:findSapling()
  while true do
    self._roomIndex = self._roomIndex + 1
    if self._roomIndex > #self._roomIds then
      self._roomIndex = 1
    end

    local nextRoomId = self._roomIds[self._roomIndex]
    self:waitAsync(1)
    self:moveTo(nextRoomId)

    if not self._lastPacket or not rex.match(self._lastPacket, "^\\[ obvious exits: .* \\]$", 1, "m") then
      self:lookWithRetry()
    end

    local trailing = rex.match(self._lastPacket, "^\\[ obvious exits: .* \\]$\\n([\\s\\S]*)$", 1, "m")
    local sapling = rex.match(trailing, "^A young leatherleaf begins to thicken with age\\.$", 1, "m")
    local person = rex.match(trailing, "^([A-Z][a-z]+) of .*$", 1, "m")
    if sapling and not person then
      return
    end
  end
end

function SampleController:killSapling()
  return self:basicAction("kill", {"sapling"}, {
    success = "^A stout young sapling is dead!  R\\.I\\.P\\.$",
    notHere = "^They aren't here\\.$",
    level = "^You gain a level!$",
    onslaught = "onslaught"
  }, 200)
end

function SampleController:replaceStaff()
  -- testing idea of just replacing staff with one at shop vs mending
  self:moveTo(152)
  sendAll("remove staff", "remove sword")
  sendAll("sell staff", "sell staff", "sell sword", "sell sword")
  send("buy staff")
  send("wield staff")
  self:waitAsync(5)
end

--Your first time! Was it good for you too?
--Oh, much better the second time around.
--Three times is the charm!



--lua wotdrone.SampleController:start()
--lua wotdrone.SampleController:stop()