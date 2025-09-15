--- PROPERTIES
local cfg = {
RADIUS = 0.13, --0.13
BOUNCINESS = 0.3, --0.3
FRICTION = 0.9,
GRAVITY = vec(0,-0.05,0), --0,-0.05,0
MARGIN = 0.01, -- best untouched
--- Model
MODEL_BALL = models.ball,
}


-- AUTO GENERATED
cfg.CHECK_RADIUS = 5
cfg.MODEL_BALL:setParentType("WORLD")
:scale(cfg.RADIUS)

return cfg