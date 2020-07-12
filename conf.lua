function love.conf(t)
  t.gammacorrect = true

  -- Disabled to avoid audio library error on early exit
  t.modules.audio = false

  -- Defer window creation to main.lua to avoid window flicker on early exit
  t.modules.window = false
end
