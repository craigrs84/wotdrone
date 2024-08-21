wotdrone = wotdrone or {}
wotdrone.Globals = wotdrone.Globals or {}
local Globals = wotdrone.Globals

Globals.RegexPatterns = {
  prompt = rex.new("^(([o*])?(?: ([RSF]))? HP:(\\w+)(?: [SD]P:(\\w+))? MV:(\\w+)(?: - (.+?): (\\w+))? > )+(.*)$")
}

Globals.EnvTypes = {
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