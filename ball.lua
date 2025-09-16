---@diagnostic disable: unused-local, redefined-local
--[[______   __
  / ____/ | / / by: GNamimates, Discord: "@gn8.", Youtube: @GNamimates
 / / __/  |/ / Golf Ball ball
/ /_/ / /|  / 
\____/_/ |_/ Source: link]]

local cfg = require"cfg"
local ball = {
	lpos = vec(0,0,0),
	pos = vec(0,0,0),
	vel = vec(0,0,0),
	isUnderwater = false,
	mat = matrices.mat4():scale(cfg.RADIUS,cfg.RADIUS,cfg.RADIUS)
}
local Trail = require"lib.trail"

local club = models.club
club:setPos(0, 0, 0)
club:setRot(0, 0, 0)  -- degrees
club:setScale(1, 1, 1)
club:setVisible(false)

-- Per-surface tuning (IDs are substring checks)
local SURF =
{
  ICE = { ids={"ice"},           friction=0.99,  boost=0.02 },      -- plain ice
  PKI = { ids={"packed_ice"},    friction=0.995, boost=0.038 },     -- packed ice
  BLI = { ids={"blue_ice"},      friction=0.999, boost=0.086 },     -- blue ice (fastest)
  SLM = { ids={"slime_block"},   bounce=1.5,    friction=0.90 },   -- lively bounce
  HNY = { ids={"honey_block"},   bounce=0.05,    friction=0.6  },   -- sticky
}

local function matchSurf(id)
  id = id or ""
  for k, s in pairs(SURF) do
    for _,needle in ipairs(s.ids) do
      if id:find(needle, 1, true) then return k, s end
    end
  end
end


function events.item_render(item)
	if item.id:find("stick") then
		if item.id == "minecraft:stick" then
		  return club.ItemClub
		end
	end
end

local trailX = Trail.new()
:setDuration(30):setDivergeness(0)  -- Reduced from 60 to 30 for better performance
local trailY = Trail.new()
:setDuration(30):setDivergeness(0)
local trailZ = Trail.new()
:setDuration(30):setDivergeness(0)

-- Trail update optimization
local trailUpdateCounter = 0


local TEXTURE_SHADOW = textures["textures.shadow"]
local SHADOW_RES = TEXTURE_SHADOW:getDimensions()
local MODEL_SHADOW = models:newPart("shadow","WORLD")
MODEL_SHADOW:newSprite("shadow"):setRenderType("BLURRY")
:texture(TEXTURE_SHADOW,SHADOW_RES:unpack()):rot(90,0,0):pos(cfg.RADIUS*16,0.5,cfg.RADIUS*16):scale((SHADOW_RES.x/16)*cfg.RADIUS*2,(SHADOW_RES.x/16)*cfg.RADIUS*2,0)

local TEXTURE_INVISIBLE = textures["textures.invisible"]
local INVISIBLE_RES = TEXTURE_INVISIBLE:getDimensions()
local MODEL_INVISIBLE = models:newPart("invisible","WORLD")
MODEL_INVISIBLE:newSprite("icon"):setRenderType("CUTOUT_EMISSIVE_SOLID")
:texture(TEXTURE_INVISIBLE,INVISIBLE_RES:unpack()):rot(90,0,0):pos(cfg.RADIUS*16,0,cfg.RADIUS*16):scale((16/INVISIBLE_RES.x)*cfg.RADIUS*2,(16/INVISIBLE_RES.x)*cfg.RADIUS*2,0)

--- caches
local side2dir = {
   ["north"] = vectors.vec3(0,0,1),
   ["east"]  = vectors.vec3(1,0,0),
   ["south"] = vectors.vec3(0,0,-1),
   ["west"]  = vectors.vec3(-1,0,0),
   ["up"]    = vectors.vec3(0,1,0),
   ["down"]  = vectors.vec3(0,-1,0),
}

local proxyShapes = {
	carpet = {
		{
			vec(0,-0.1,0),
			vec(1,0,1),
		},
	},
}

events.ENTITY_INIT:register(function ()
	ball.pos = player:getPos():add(0,1,0)
end)

local windSoundCooldown = 0
local blocks = {}
local blocksRaw = {}
local lbpos = vec(0,0,0)
local blockCache = {} -- Cache for block states and shapes
local framesSinceUpdate = 0

-- Performance monitoring (optional - can be removed)
local perfStats = {
	blocksChecked = 0,
	cacheHits = 0,
	lastReport = 0
}

-- Optimized block detection with caching and distance culling
local function updateBlockCollisions(ballPos)
	local bpos = ballPos:floor()
	if bpos == lbpos and framesSinceUpdate < 3 then -- Reduced from 5 to 3 for faster updates
		framesSinceUpdate = framesSinceUpdate + 1
		return -- Skip update unless position changed or 3 frames passed
	end
	
	lbpos = bpos
	framesSinceUpdate = 0
	blocks = {}
	blocksRaw = {}
	local i = 1
	
	-- Dynamic radius optimized for speed-limited clubs
	local speed = ball.vel:length()
	-- Much more conservative scaling since we now have speed limits (max 2.5)
	local dynamicRadius = math.min(cfg.CHECK_RADIUS, math.max(3, math.ceil(speed * 1.2 + 3)))
	
	-- Reduce predictive collision threshold since speeds are now capped
	local predictivePositions = {}
	if speed > 2.0 then -- Raised threshold since max speed is only 2.5
		-- Fewer prediction steps since speeds are controlled
		local currentPos = ballPos
		local currentVel = ball.vel
		for step = 1, math.min(3, math.ceil(speed * 0.8)) do -- Reduced prediction steps
			currentPos = currentPos + currentVel
			currentVel = currentVel + cfg.GRAVITY -- Account for gravity
			table.insert(predictivePositions, currentPos:floor())
		end
	end
	
	-- Use squared distance to avoid sqrt calculations
	local radiusSquared = dynamicRadius * dynamicRadius
	
	-- Collect all positions to check (current + predictive)
	local positionsToCheck = {bpos}
	for _, predPos in ipairs(predictivePositions) do
		-- Avoid duplicates
		local isDuplicate = false
		for _, existingPos in ipairs(positionsToCheck) do
			if existingPos.x == predPos.x and existingPos.y == predPos.y and existingPos.z == predPos.z then
				isDuplicate = true
				break
			end
		end
		if not isDuplicate then
			table.insert(positionsToCheck, predPos)
		end
	end
	
	-- Limit total block checks - more generous since speeds are now capped
	local baseMaxChecks = math.min(cfg.CHECK_RADIUS * 50, 3000) -- Cap absolute maximum
	local maxChecks = speed > 2.0 and baseMaxChecks or (speed > 1.0 and baseMaxChecks * 1.2 or baseMaxChecks * 1.5)
	local checksPerformed = 0
	
	-- Check blocks around all predicted positions
	for _, checkPos in ipairs(positionsToCheck) do
		if checksPerformed >= maxChecks then break end
		
		-- Use smaller radius for predictive positions to stay within performance budget
		local useRadius = checkPos == bpos and dynamicRadius or math.min(dynamicRadius, math.max(4, cfg.CHECK_RADIUS / 3))
		local useRadiusSquared = useRadius * useRadius
		
		for z = -useRadius, useRadius do
			if checksPerformed >= maxChecks then break end
			for y = -useRadius, useRadius do
				if checksPerformed >= maxChecks then break end
				for x = -useRadius, useRadius do
					if checksPerformed >= maxChecks then break end
					
					-- Distance culling - only check blocks within sphere, not cube
					local distSq = x*x + y*y + z*z
					if distSq <= useRadiusSquared then
						checksPerformed = checksPerformed + 1
						local offset = vec(x,y,z)
						local cpos = checkPos + offset
						local cacheKey = tostring(cpos.x) .. "," .. tostring(cpos.y) .. "," .. tostring(cpos.z)
						
						local cached = blockCache[cacheKey]
						if not cached then
							perfStats.blocksChecked = perfStats.blocksChecked + 1
							local block = world.getBlockState(cpos)
							if block:hasCollision() then
								local shape
								for match, proxyShape in pairs(proxyShapes) do
									if block.id:find(match) then
										if type(proxyShape) == "function" then
											shape = proxyShape(block,cpos)
										else
											shape = proxyShape
										end
										break
									end
								end
								shape = shape or block:getCollisionShape()
								cached = {hasCollision = true, shape = shape, id = block.id}
							else
								cached = {hasCollision = false}
							end
							blockCache[cacheKey] = cached
							
							-- More aggressive cache cleanup when moving fast
							if perfStats.blocksChecked % 100 == 0 and #blockCache > 1500 then
								local toRemove = {}
								local cleanupRadius = speed > 1.0 and cfg.CHECK_RADIUS or cfg.CHECK_RADIUS * 2
								for key, _ in pairs(blockCache) do
									local coords = {}
									for coord in key:gmatch("[^,]+") do
										table.insert(coords, tonumber(coord))
									end
									local dist = (vec(coords[1], coords[2], coords[3]) - bpos):length()
									if dist > cleanupRadius then
										table.insert(toRemove, key)
									end
								end
								for _, key in ipairs(toRemove) do
									blockCache[key] = nil
								end
							end
						else
							perfStats.cacheHits = perfStats.cacheHits + 1
						end
						
						if cached.hasCollision then
							for key, value in pairs(cached.shape) do
								blocks[i] = {value[1] + cpos - cfg.RADIUS + cfg.MARGIN, value[2] + cpos + cfg.RADIUS - cfg.MARGIN}
								blocksRaw[i] = {value[1] + cpos + cfg.MARGIN, value[2] + cpos - cfg.MARGIN}
								i = i + 1
							end
						end
					end
				end
			end
		end
	end
	
	-- Performance reporting (optional)
	if client.getSystemTime() - perfStats.lastReport > 5000 then -- Every 5 seconds
		perfStats.lastReport = client.getSystemTime()
		local cacheRatio = perfStats.cacheHits / math.max(1, perfStats.cacheHits + perfStats.blocksChecked)
		-- Uncomment to see performance stats in chat
		-- print(string.format("Golf Performance: %.1f%% cache hits, %d blocks checked, radius: %d, predictions: %d", cacheRatio * 100, perfStats.blocksChecked, dynamicRadius, #predictivePositions))
		perfStats.blocksChecked = 0
		perfStats.cacheHits = 0
	end
end

events.TICK:register(function ()
	ball.lpos = ball.pos
	-- Cap how far we can travel in one tick so raycasts don't skip geometry
	local MAX_SWEEP = (cfg.MAX_SWEEP or (cfg.CHECK_RADIUS - 1))  -- stays inside the checked cube
	local speed = ball.vel:length()
	
	-- Simple capping for very high speeds
	if speed > MAX_SWEEP and speed > 0 then
		ball.vel = ball.vel * (MAX_SWEEP / speed)
	end

	ball.pos = ball.pos + ball.vel
	
	-- Update collision data
	updateBlockCollisions(ball.pos)
	
	-- slopes
	local support = world.getBlockState(ball.pos - vec(0,cfg.RADIUS+0.2,0))
	if support.id:find("stairs") then
		local force = side2dir[support.properties.facing] * vec(-1,0,1)
		local shift = support.properties.shape:match("_(%w+)$")
		if shift then
			local perpendicular = force:cross(vec(0,1,0))
			local len = force:length()
			if shift == "left" then
				force = vectors.rotateAroundAxis(135,force,vec(0,1,0))
			else
				force = vectors.rotateAroundAxis(45,force,vec(0,1,0))
			end
		end
		ball.vel = ball.vel + force * (ball.vel-force):length() * 0.05
	end
	
	--- Waxed Copper Trapdoors as fans - optimized to only check when near potential fans
	if speed > 0.05 then -- Only check fans when ball is moving
		for side, dir in pairs(side2dir) do
			local _, hitPos = raycast:aabb(ball.pos,ball.pos + dir * 5,blocks)
			if hitPos then
				local block = world.getBlockState(hitPos)
				if block.id == "minecraft:waxed_copper_trapdoor" and (((side == "up" or side == "down") and "false" or "true") == block.properties.open) then
					ball.vel = ball.vel * 0.9 - dir * 0.08
					windSoundCooldown = windSoundCooldown - 1
					if windSoundCooldown < 0 then
						windSoundCooldown = 5
						sounds:playSound("minecraft:entity.breeze.slide",ball.pos,1,1)
					end
				end
			end
		end
	end
	
	-- Moving Piston pushes the ball
	local block = world.getBlockState(ball.pos)
	if block.id == "minecraft:moving_piston" then
		ball.vel = ball.vel + side2dir[block.properties.facing] * 0.5
	end
	
	-- Fluid
	if #block:getFluidTags() > 0 then
		if not ball.isUnderwater then
			ball.isUnderwater = true
			sounds["minecraft:entity.generic.splash"]:pos(ball.pos):pitch(1):play()
			for _ = 1, 10, 1 do
				particles["minecraft:splash"]:pos(ball.pos):spawn()
			end
			particles["minecraft:cloud"]:pos(ball.pos):spawn()
		end
		ball.vel = ball.vel * 0.7
	else
		if ball.isUnderwater then
			ball.isUnderwater = false
		end
	end
	-- Robust slime detection around the contact
local function _slimeId(id)
  return id and id:find("slime_block", 1, true) ~= nil
end

local function _idAt(p)
  local s = world.getBlockState(p); return s and s.id or ""
end

local function isSlimeContact(hit, norm)
  -- sample inside/outside the contact
  if _slimeId(_idAt(hit - norm * 0.01)) or _slimeId(_idAt(hit + norm * 0.01)) then
    return true
  end
  -- also probe straight below the sphere center (catches grazing/edge cases)
  local belowProbe = ball.pos - vec(0, cfg.RADIUS + 0.01, 0)
  return _slimeId(_idAt(belowProbe))
end

	--- Multi-layer protection against tunneling through blocks
	-- Primary: Standard raycast protection
	local _, hit, face = raycast:aabb(ball.lpos, ball.pos, blocksRaw)
	if face then
	  local norm = side2dir[face]
	  ball.pos = hit + cfg.MARGIN * norm
	end


	local _, hit, face = raycast:aabb(ball.lpos, ball.pos, blocks)
if face then
  local norm = side2dir[face]
  local flat = (ball.vel - norm * ball.vel:dot(norm))
  local absorbed = (flat - ball.vel)

  -- Look up the surface block we actually hit
  local surfacePos = hit - norm * (cfg.RADIUS + cfg.MARGIN)
  local surface    = world.getBlockState(surfacePos)
  local sid        = surface and surface.id or ""
  local key, S     = matchSurf(sid)

  -- Defaults from your cfg, then tweak per surface
  local localFriction  = cfg.FRICTION
  local localBounciness = cfg.BOUNCINESS
  local alongBoost     = 0

  if S then
    if S.friction  then localFriction  = S.friction  end
    if S.bounce    then localBounciness = S.bounce    end
    if S.boost     then alongBoost     = S.boost     end
  end

  -- Standard bounce detection - keep it simple and reliable
  local willBounce = (absorbed + cfg.GRAVITY):length() * 10 > localBounciness

  -- Compute base post-collision velocity
  local v = flat * localFriction + (absorbed) * (willBounce and localBounciness or 0)

  -- ICE "speed strip": floor contact only (norm.y > 0) – push along tangent
  if key and (key == "ICE" or key == "PKI" or key == "BLI") and norm.y > 0.5 then
    local flen = flat:length()
    if flen > 0.0001 then
      v = v + flat / flen * alongBoost
    end
  end

  -- SLIME: robust, guaranteed floor bounce
if (key == "SLM" or isSlimeContact(hit, norm)) and ball.vel.y < -0.01 then
  -- If the face normal is a bit sideways (edge/tolerance), treat as floor
  local N = (norm.y > 0.2) and norm or vectors.vec3(0,1,0)

  -- Restitution & tangent keep
  local e  = (S and S.bounce)   or 1.35           -- try 1.25–1.55
  local mu = (S and S.friction) or localFriction  -- 0.88–0.95 keeps some slide

  local vn    = ball.vel:dot(N)                   -- < 0 on downward impact
  local v_tan = ball.vel - N * vn

  -- Reflect normal, keep tangent with friction
  v = v_tan * mu - N * vn * e
  willBounce = true

  -- Small deadzone to avoid micro-jitter on feather touches
  if math.abs(v.y) < 0.005 then v.y = 0 end
end


  -- HONEY:
  --  - floors: extra sticky (handled by low friction above)
  --  - walls: prevent vertical free-fall; make it slide slowly instead
  if key == "HNY" and math.abs(norm.y) < 0.5 then
    -- clamp downward speed; keep a gentle slide
    v.y = math.max(v.y, -0.01)
    -- add a small along-wall damping so it "clings"
    v = v * 0.9
  end

  ball.vel = v
  ball.pos = hit + cfg.MARGIN * norm

  if willBounce then
    local bsounds = surface:getSounds()
    if bsounds and bsounds.hit then
      sounds[bsounds["step"]]:pitch(2):volume(2):pos(hit):play()
    end
  end
else
  ball.vel = ball.vel + cfg.GRAVITY
end

end)

function ball.update(delta)
	local tpos = math.lerp(ball.lpos, ball.pos, delta)
	ball.mat.c4 = vec(0,0,0,1)
	local vel = ball.vel * 2
	ball.mat:rotateX(math.deg(vel.z))
	ball.mat:rotateZ(math.deg(-vel.x))
	ball.mat.c4 = (tpos * 16):augmented(1)
	
	-- Optimized trail update throttling for speed-limited system
	trailUpdateCounter = trailUpdateCounter + 1
	local speed = ball.vel:length()
	-- Since max speed is now 2.5, adjust thresholds
	local updateFreq = speed > 2.0 and 4 or (speed > 1.0 and 3 or 2) -- More frequent since speeds are controlled
	local shouldUpdateTrails = trailUpdateCounter % updateFreq == 0
	
	if shouldUpdateTrails then
		local dx = vec(1,0,0)
		local dy = vec(0,1,0)
		local dz = vec(0,0,1)
		
		trailX:setLeads(tpos - dx, tpos + dx,cfg.RADIUS)
		trailY:setLeads(tpos - dy, tpos + dy,cfg.RADIUS)
		trailZ:setLeads(tpos - dz, tpos + dz,cfg.RADIUS)
	end
	
	cfg.MODEL_BALL:setMatrix(ball.mat:copy())
	-- shadow - update more frequently since speeds are now controlled
	if speed < 2.5 then -- Update shadow for all normal speeds
		local sto = tpos + vec(0,-5,0)
		local _,shit = raycast:block(tpos,sto)
		if (sto - shit):lengthSquared() ~= 0 then
			MODEL_SHADOW:setPos(shit*16):setVisible(true)
		else
			MODEL_SHADOW:setVisible(true)
		end
	end
end

cfg.MODEL_BALL.preRender = function (delta, context, part)
	local tpos = math.lerp(ball.lpos, ball.pos, delta)
	local mat = matrices.mat4()
	local cpos = client:getCameraPos()
	local dir = tpos - cpos
	local look = dir:normalized()
	local block,pos = raycast:block(tpos,cpos,"VISUAL")
	if (pos-cpos):lengthSquared() > 0.01 then
		MODEL_INVISIBLE:setPos((tpos - dir*0.9)*16):rot(90+math.deg(-math.asin(look.y)),90-math.deg(math.atan2(dir.z,dir.x))):scale(0.1,0.1,0.1):setVisible(true)
	else
		MODEL_INVISIBLE:setVisible(false)
	end
end

-- --- tuning knobs -----------------------------------------------------------
local POS_EPS      = 0.1   -- send if position changed more than this (blocks)
local VEL_EPS      = 0.1   -- send if velocity changed more than this
local SLOW_SPEED   = 0.09   -- below this, we consider the ball "slow/still"
local KEEPALIVE_S  = 10      -- always ping at least this often (seconds)
-- ---------------------------------------------------------------------------

local function len2(v) return v.x*v.x + v.y*v.y + v.z*v.z end

ball.lastPingPos  = ball.lastPingPos or ball.pos
ball.lastPingVel  = ball.lastPingVel or ball.vel
ball.lastPingTime = ball.lastPingTime or client.getSystemTime()/1000
ball.wasMoving    = ball.wasMoving or false

function ball.maybePing()
  local now = client.getSystemTime()/1000 -- if not available, use client.getSystemTime()/1000
  local speed2   = len2(ball.vel)
  local moved2   = len2(ball.pos - ball.lastPingPos)
  local dvel2    = len2(ball.vel - ball.lastPingVel)
  local slow2    = SLOW_SPEED * SLOW_SPEED
  local pos_eps2 = POS_EPS * POS_EPS
  local vel_eps2 = VEL_EPS * VEL_EPS

  local shouldSend =
      moved2 > pos_eps2 or                   -- noticeable position change
      dvel2  > vel_eps2 or                   -- noticeable velocity change
      (now - ball.lastPingTime) >= KEEPALIVE_S or  -- keep-alive
      (ball.wasMoving and speed2 <= slow2)   -- one last ping when it comes to rest

  if shouldSend then
    pings.state(ball.pos, ball.vel)
    ball.lastPingPos  = ball.pos
    ball.lastPingVel  = ball.vel
    ball.lastPingTime = now
    ball.wasMoving    = speed2 > slow2
  end
end

function ball.forcePing()
	pings.state(ball.pos,ball.vel)
end

function pings.state(p,v)
	ball.pos = p
	ball.vel = v
end

function pings.shoot(vel)
	ball.vel = ball.vel + vel
end

if host:isHost() then
local pingTimer = 0
events.WORLD_TICK:register(function ()
	pingTimer = pingTimer + 1
	if pingTimer > 20 then
		pingTimer = 0
		ball.maybePing()
	end
end)
end
function pings.resetBallPos()
	ball.pos = player:getPos():add(0,1,0)
	ball.vel = vec(0,0,0)
end

local myPage = action_wheel:newPage()
action_wheel:setPage(myPage)
-- === One-button color cycler for the golf ball ===
-- Assumes your Blockbench texture key is "golf ball" (from "golf ball.png")
local BALL_TEX = textures:getTextures()[1]
-- multiply the texture by an RGB vec (0..1)
local function tintBall(rgb)
  if not BALL_TEX then return end
  local dim = BALL_TEX:getDimensions()
  BALL_TEX
    :restore()                                        -- start from original pixels
    :applyMatrix(0, 0, dim.x, dim.y, matrices.mat4():scale(rgb))
    :update()
end

-- tweak these or add more
local colors = {
  {name="White",  rgb=vec(1, 1, 1),   item="minecraft:white_dye"},
  {name="Gray",  rgb=vec(0.5, 0.5, 0.5),   item="minecraft:gray_dye"},
  {name="Black",  rgb=vec(0,0,0), item="minecraft:black_dye"},
  {name="Brown",  rgb=vec(0.59,0.29,0), item="minecraft:brown_dye"},
  {name="Red",    rgb=vec(1, 0.3,0.3),item="minecraft:red_dye"},
  {name="Orange",  rgb=vec(1,0.647,0), item="minecraft:orange_dye"},
  {name="Yellow", rgb=vec(1, 1, 0),   item="minecraft:yellow_dye"},
  {name="Lime",  rgb=vec(0,1,0), item="minecraft:lime_dye"},
  {name="Green",  rgb=vec(0.6,1,0.6), item="minecraft:green_dye"},
  {name="Cyan",  rgb=vec(0,1,1), item="minecraft:cyan_dye"},
  {name="Blue",   rgb=vec(0.4,0.6,1), item="minecraft:blue_dye"},
  {name="Purple",  rgb=vec(0.5,0,0.5), item="minecraft:purple_dye"},
  {name="Pink",  rgb=vec(1,0.75,0.79), item="minecraft:pink_dye"},
}

local colorIdx = 1
local colorAction -- forward-declare so we can update its UI

local function applyColor(idx)
  colorIdx = ((idx - 1) % #colors) + 1
  local c = colors[colorIdx]
  tintBall(c.rgb)
  if colorAction then
    colorAction:setTitle("Ball Color: " .. c.name)
               :setItem(c.item)
               :setHoverColor(c.rgb.x, c.rgb.y, c.rgb.z)
  end
end

-- broadcast so all players see the same color
function pings.setBallColor(idx)
  applyColor(idx)
end

-- use your existing page, or create one if needed:
-- local page = action_wheel:newPage()

colorAction = myPage:newAction()
  :setTitle("Ball Color")
  :setItem(colors[colorIdx].item)
  :setHoverColor(1, 1, 1)
  :onLeftClick(function()
    local nextIdx = colorIdx % #colors + 1
    pings.setBallColor(nextIdx)
  end)
  :onRightClick(function()
    local prevIdx = (colorIdx - 2) % #colors + 1
    pings.setBallColor(prevIdx)
  end)

applyColor(colorIdx)      -- init UI + tint
-- action_wheel:setPage(page)  -- ensure your page is active if not already




local myBallSpawn = myPage:newAction()
myBallSpawn:setTitle("Spawn Ball")
myBallSpawn:setItem("wind_charge")
myBallSpawn:setOnLeftClick(pings.resetBallPos)


-- Camera Follow Toggle Action
local cameraFollowAction = myPage:newAction()
cameraFollowAction:setTitle("Camera Follow")
cameraFollowAction:setItem("minecraft:ender_eye")
cameraFollowAction:setToggleItem("minecraft:ender_pearl")
cameraFollowAction:setOnToggle(function(state)
	pings.setCameraFollow(not state)
	cameraFollowAction:setTitle(not state and "Camera: Follow" or "Camera: Free")
	if state then
		renderer:setCameraPivot()
		renderer:renderLeftArm()
		renderer:renderRightArm()
		renderer:setRenderHUD(true)
	end
end)
return ball