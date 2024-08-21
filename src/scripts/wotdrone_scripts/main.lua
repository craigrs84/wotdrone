wotdrone = wotdrone or {}
wotdrone.Main = wotdrone.Main or {}
local Main = wotdrone.Main

function Main:handleLoad(event, name)
  if event == "sysLoadEvent" or name == "wotdrone" then
    cecho("\n<orange>WotDrone: Loaded\n")
    wotdrone.RoomWeights.initialize()
    wotdrone.EventDispatcher:start()
  end
end

function Main:handleExit(event, name)
  if event == "sysExitEvent" or name == "wotdrone" then
    cecho("\n<orange>WotDrone: Unloaded\n")
    wotdrone.EventDispatcher:stop()
    wotdrone = nil
  end
end

registerAnonymousEventHandler("sysInstallPackage", "wotdrone.Main:handleLoad")
registerAnonymousEventHandler("sysLoadEvent", "wotdrone.Main:handleLoad")
registerAnonymousEventHandler("sysUninstallPackage", "wotdrone.Main:handleExit")
registerAnonymousEventHandler("sysExitEvent", "wotdrone.Main:handleExit")