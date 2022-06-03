
// returns a list of non-null indices for list object
list.nonNullInds = function()
  inds = self.indexes
  out = [] // output list
  for i in inds
    if ((not self[i]) == 0) then out.push i
  end for
  return out
end function

// checks if a string is the name of a trellis "seed" (starter)
// use with bot.inventory[i].
string.isTrellis = function()
  out = false
  if self == "Bean Starter" then
    out = true
  else if self == "Hops Starter" then
    out = true
  else if (self == "Grape Starter") or (self == "Summer Seeds") then
    out = true
  end if
  return out
end function

// gets info about seeds in bot inventory.
// trellisOK=false will exclude trellis seeds from output (default true).
// returns map (dict) with two items:
//   idx: integer, indices of seeds in bot inventory
//   qty: integer, qantity ("stack") of seeds
bot.seedMap = function(trellisOK=true)
  inds = self.inventory.nonNullInds
  out = {} // output map
  out.idx = [] // indices of seeds
  out.qty = [] // quantities of seeds
  for i in inds
    if trellisOK then
      // trellis is ok, add if seed
      if self.inventory[i].category == "Seed" then out.idx.push i
    else
      // trellis is not ok, check for that
      if (self.inventory[i].category == "Seed") and (not self.inventory[i].name.isTrellis) then
        out.idx.push i
      end if
    end if
  end for
  for i in out.idx
    out.qty.push self.inventory[i].stack
  end for
  return out
end function

// cumulative sum of a list of numbers x
cumSum = function(x)
  cs = []
  for i in x.indexes
    if i == 0 then 
      cs.push x[i]
    else 
      cs.push x[i] + cs[i - 1]
    end if
  end for
  return cs
end function

// weighted random index from list of category weights
// w is a list of numbers representing weights
// (only tested with integers, but may work for floats)
// returns one index of w (an int)
sampleCats = function(w)
  // total sum of cats
  cs = cumSum(w)
  cutoff = rnd * cs[cs.len - 1]
  for i in w.indexes // basically enum(w)
    if cutoff < cs[i] then return i
  end for
  return null
end function

// returns a random index of a seed object in inventory, weighted by
// the stack height of seed objects. Setting trellisOK=false (default)
// will ignore trellis seeds (and potential trellis seeds)
bot.getRandSeed = function(trellisOK=false)
  sm = self.seedMap(trellisOK)
  if sm.idx.len > 0 then
    i = sm.idx[sampleCats(sm.qty)]
    return self.inventory[i].name
  else
    return null
  end if
end function

// position plus direction plus magnitude
// x is x position from bot.position.x
// y is y position
// d is direction from bot.facing (0123)
// m is magnitude in number of steps
// returns map with x and y coordinates
posPlusDir = function(x, y, d=0, m=1)
  // make v, a vector to add to [x,y]
  if d % 2 then 
    v = [1,0] // d is 1 or 3, meaning E or W
    // print "13ew"
  else
    v = [0,1] // d is 2 or 0, meaning N or S
    // print "02ns"
  end if
  if not d % 3 then // "if d is 0 or 3", so go negative for right or down.
    v.push(v.pull * -1 * m)
    v.push(v.pull * -1 * m)
    // print "neg"
  end if
  return {"x":x+v[0], "y":y+v[1]}
end function


direction_left = function(d)
  if d == 0 then
    return 3
  else
    return d - 1
  end if
end function

direction_right = function(d)
  if d == 3 then
    return 0
  else
    return d + 1
  end if
end function

// coordinates of front, left, and right positions of bot
// returns map with three items: front, left, right, rear. each is a map with x and y.
bot.adjacentPos = function(rear=true)
  bp = {"x":self.position.x, "y":self.position.y, "d":self.facing}
  out = {}
  out.front = posPlusDir(bp.x, bp.y, bp.d)
  out.left = posPlusDir(bp.x, bp.y, direction_left(bp.d))
  out.right = posPlusDir(bp.x, bp.y, direction_right(bp.d))
  if rear then out.rear = posPlusDir(bp.x, bp.y, (bp.d +2) % 4)
  return out
end function

// contains method for lists, checks if any item in list is exactly x
list.contains = function(x)
  for i in self.indexes
    if self[i] == x then return 1
  end for
  return 0
end function

// contains method for maps, checks if any item in map is exactly x
map.contains = function(x)
  for i in self.indexes
    if self[i] == x then return 1
  end for
  return 0
end function


// gets key from position, null if empty
// key arguments (not complete): "type" "name"
// pos is a map containing "x" and "y" coords at least, ex: bot.adjacentPos.front
posKey = function(pos, key="name")
  tl = farm.tile(pos.x, pos.y)
  if not tl isa map then
    return null
  else if tl.hasIndex(key) then
    return tl[key]
  else
    return null
  end if
end function

// plants a random seed right ahead, but not a trellis if trelOK=false
bot.randPlant = function(trelOK=false)
  seedName = self.getRandSeed(trelOK)
  if seedName then // only keep going if there *is* a seed
    self.select(seedName)
    self.placeItem
  end if
end function

// finds name of first fertilizer in inventory
bot.getFertName = function()
  for item in self.inventory
    if item isa map then
      if item.category == "Fertilizer" then return item.name
    end if
  end for
  return null
end function


// applies fertilizer if any in inventory
// does NOT check if tile in front of bot is appropriate for this
bot.fertilize = function()
  fertName = self.getFertName
  if fertName then
    self.select(fertName)
    self.placeItem
  end if
end function

bot.turn180 = function()
  bot.left
  bot.left
end function

// general farming function. bot does all kinds of stuff:
//   if not hoedirt, not crafting: bot.clearAhead and hoe
//   if detects hoedirt:
//     if plant:
//       if harvestable, harvest
//     if no plant: (NOTE: NOT ELSE)
//       fertilizes
//       plants seed (non-trellis if dir == "front")
//     waters
//   if detects water: use watering can
//   else if detects sign:
//     if wood, return instruction "right turn"
//     else if stone, instruction "left turn"
//   else if detects gate:
//     return instruction "return to base"
//   else return null
//
//  arguments:
//  direction is "front", "right", "left", "rear"
//  
//  returns string instruction (See above)
//   
bot.farmDirection = function(direction="front")
  // face direction
  if direction == "right" then self.right
  if direction == "left" then self.left
  if direction == "rear" then self.turn180
  pos = self.adjacentPos.front
  // check if clearing should be done. if so, clear and hoe
  dontClear = ["HoeDirt", "Wood Sign", "Stone Sign", "Gate", "Scarecrow", "Water"]
  if not dontClear.contains(posKey(pos, "name")) then
    self.clearAhead
    self.select("Hoe")
    self.useTool
  end if
  // handle existing crop, maybe harvest
  if(posKey(pos, "crop")) then
    // it's a crop. if it's harvestable, do it. otherwise, water it if dry
    cropnfo = farm.tile(pos.x, pos.y).crop
    if cropnfo.harvestable == 1 then
      if cropnfo.harvestMethod then
        // 1 means scythe
        self.select("Scythe")
        self.useTool
      else
        // 0 means regular harvest
        self.harvest
      end if
    else if posKey(pos, "dry") then
      // it's a crop but isn't ready yet. and it's dry. water it
      self.select("Watering Can")
      self.useTool
    end if
  end if
  // if there's nothing there now, hoe that dirt
  if not posKey(pos, "type") then
    self.select("Hoe")
    self.useTool
  end if
  // if there's hoeDirt and no crop, plant stuff
  if (posKey(pos, "name") == "HoeDirt") and (not posKey(pos, "crop")) then
    // no way to tell if HoeDirt is already fertilized. Just apply it anyway, since
    // it won't get used unless needed.
    self.fertilize
    if ["left", "right"].contains(direction) then
      // make sure there's no sign around, otherwise trellis could obstruct turning
      adjPos = self.adjacentPos(true) // true means to look at rear too
      adjNames = adjPos.apply(@posKey)
      if adjNames.contains("Wood Sign") or adjNames.contains("Stone Sign") then
        self.randPlant(false) // false means no trellis allowed
      else
        self.randPlant(true) // true means trellis is OK
      end if
    else
      self.randPlant(false) // false means no trellis allowed in bot pathaw
    end if
    self.select("Watering Can")
    self.useTool
  end if
  // refill water if possible
  // NOTE - need to update for well, maybe.
  if posKey(pos, "name") == "Water" then
    self.select("Watering Can")
    self.useTool
  end if
  // handle output (sensing signs and stuff)
  out = null
  if posKey(pos, "name") == "Wood Sign" then out = "Wood Sign"
  if posKey(pos, "name") == "Stone Sign" then out = "Stone Sign"
  if posKey(pos, "name") == "Gate" then out = "Gate"
  // re-orient
  if direction == "right" then self.left
  if direction == "left" then self.right
  if direction == "rear" then self.turn180
  // return
  return out
end function

// gets remaining watering can uses
bot.waterLvl = function()
  for i in self.inventory.indexes
    if self.inventory[i].name == "Watering Can" then break
  end for
  return self.inventory[i].waterLeft
end function

// apply function takes map m and function f,
// applies f to each item in map, and returns them 
// as a map with the same keys as m. not that f
// can't be a method, it must be a function that
// takes a single argument which can be any value
// in m. This is best suited for homogenous maps.
// REMEMBER TO USE @ before function to pass it.
map.apply = function(f)
  inds = self.indexes
  out = {}
  for i in inds
    out[i] = f(self[i])
  end for
  return out
end function


// returns bot back to home, fetching water along the way
// similar to bot.getWater.
bot.home = function()
  // do a 180
  self.left
  self.left
  while true
    // look for signs, do OPPOSITE as bot.farmWrap
    adjPos = self.adjacentPos(false)
    adjNames = adjPos.apply(@posKey)
    // refill on way home, so full next time
    if adjNames.contains("Water") then
      // which dir contains water?
      adjPos = self.adjacentPos(false)
      adjNames = adjPos.apply(@posKey)
      for dir2turn in adjNames.indexes
        if adjNames[dir2turn] == "Water" then break
      end for
      if dir2turn == "right" then
        self.right
        self.select("Watering Can")
        self.useTool
        self.left
      else if dir2turn == "left" then
        self.left
        self.select("Watering Can")
        self.useTool
        self.right
      else
        self.select("Watering Can")
        self.useTool
      end if
    end if
    if adjNames.contains("Wood Sign") then self.left
    if adjNames.contains("Stone Sign") then self.right
    // if done, break
    if adjNames.contains("Gate") then break
    // advance
    self.forward
  end while
  self.left
  self.left
end function

antiRL = function(direction)
  if direction == "left" then 
    return "right"
  else if direction == "right" then
    return "left"
  else 
    return direction
  end if
end function

// turns around and fetches water, then turns around again.
bot.getWater = function()
  // do a 180
  self.left
  self.left
  while true
    // look for signs, do OPPOSITE as self.farmWrap
    adjPos = self.adjacentPos(false)
    adjNames = adjPos.apply(@posKey)
    if adjNames.contains("Wood Sign") then self.left
    if adjNames.contains("Stone Sign") then self.right
    // look for water
    if adjNames.contains("Water") then
      // which dir contains water?
      adjPos = self.adjacentPos(false)
      adjNames = adjPos.apply(@posKey)
      for dir2turn in adjNames.indexes
        if adjNames[dir2turn] == "Water" then break
      end for
      if dir2turn == "right" then
        self.right
        self.select("Watering Can")
        self.useTool
        self.left
      else if dir2turn == "left" then
        self.left
        self.select("Watering Can")
        self.useTool
        self.right
      else
        self.select("Watering Can")
        self.useTool
      end if
    end if
    if self.waterLvl > 30 then
      self.left
      self.left
      break
    else
      self.forward
    end if
  end while
end function

// step function, handles every movement and decision of bot
// at any given step along its journey. 
// this function is a wrapper for the robot to proceed to the
// next space. it may send the robot back to get water, which
// is ok because then this function can be called again until
// the robot reaches its former spot (since water will no longer
// be required). The function assumes the robot has just moved - 
// in other words, moving is the last thing done by this function.
// Gate       - home
// Wood Sign  - turn right
// Stone Sign - turn left
bot.farmStep = function(farmRear=false)
  // farm front, left, right, saving any messages
  msgs = []
  msgs.push self.farmDirection("left")
  msgs.push self.farmDirection("right")
  msgs.push self.farmDirection("front")
  if farmRear then
    trash = self.farmDirection("rear")
  end if

  // check water lvl. if under 3, getWater
  if self.waterLvl < 3 then self.getWater

  // check if wood sign in any messages. if so, 
  // turn. go home if gate. still turn if water
  // was just fetched, because water could be at a turn
  // and water stops once filled and 180'd.
  if msgs.contains("Gate") or (self.energy < 3) then
    self.home
    return "done"
  else if msgs.contains("Wood Sign") then
    self.right
  else if msgs.contains("Stone Sign") then
    self.left
  end if

  // proceed to next tile
  self.forward

end function


// farm function, calls bot.farmStep and therefore everything else
bot.farm = function()
  done = null
  while not done
    done = self.farmStep(false)
  end while
end function

// log        type=crafting, name=Twig
// stone      type=Basic,    name="Stone"
// wood sign  type=crafting, name=Wood Sign
// hoedirt    type=HoeDirt, name=HoeDirt
// weed       type=Basic,   name=Weeds
// grass      type=Grass,    name=Grass


// turns bot to face away from gate
// returns 1 if a gate was found and bot turned
// away from it, otherwise returns 0
bot.faceAwayFromGate = function()
  posmap = self.adjacentPos(true)
  names = posmap.apply(@posKey) //note default param of posKey is "name"
  if names.left == "Gate" then
    self.left
  else if names.right == "Gate" then
    self.right
  else if names.front == "Gate" then
    self.left
    self.left
  else if names.rear == "Gate" then
    print "hooray"
  else
    return 0
  end if
  return 1
end function
