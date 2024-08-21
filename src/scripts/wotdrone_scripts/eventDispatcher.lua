wotdrone = wotdrone or {}
wotdrone.EventDispatcher = wotdrone.EventDispatcher or {}
local EventDispatcher = wotdrone.EventDispatcher
local RegexPatterns = wotdrone.Globals.RegexPatterns

function EventDispatcher:start()
  self._lastLine = nil
  self._lastPacket = nil
  self._packet = ""
  self:createLineTrigger()
end

function EventDispatcher:stop()
  self:killLineTrigger()
end

function EventDispatcher:createLineTrigger()
  self._lineTriggerId = tempRegexTrigger(f"^.*$", function()
    self._lastLine = line
    raiseEvent("wotmudLine", line)

    local prompt, _, _, _, _, _, _, _, trailing = RegexPatterns.prompt:match(line)
    if prompt ~= nil then
      --prompt
      self._packet = self._packet .. prompt .. "\n"
      
      self._lastPacket = self._packet
      raiseEvent("wotmudPacket", self._packet)
      
      self._packet = trailing:len() > 0 and trailing .. "\n" or ""
    else
      --not prompt
      self._packet = self._packet .. line .. "\n"
    end
  end)
end

function EventDispatcher:killLineTrigger()
  disableTrigger(self._lineTriggerId or 0)
  killTrigger(self._lineTriggerId or 0)
  self._lineTriggerId = nil
end