local ball = require"ball"
local cfg = require"cfg"

events.TICK:register(function ()
	local cpos = player:getPos():add(0,player:getEyeHeight())
	local cdir = player:getLookDir()
	local isHighlightingBall = cdir:dot((ball.pos-cpos):normalize()) > 0.999
end)