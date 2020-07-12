function love.conf(t)
  t.gammacorrect = true

  -- Created in main.lua to avoid flickering window on invalid command line
  t.modules.window = false
end
