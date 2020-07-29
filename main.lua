local argparse = require("argparse")
local Editor = require("gutter.Editor")
local Slab = require("Slab")

function love.load(arg)
  local parser = argparse("love <directory>", "Mesh and draw a CSG model")

  parser:flag("--fullscreen", "Enable fullscreen mode")
  parser:flag("--high-dpi", "Enable high DPI mode")

  parser:option("--mesher", "Meshing algorithm"):args(1)
  parser:option("--msaa", "Antialiasing samples"):args(1):convert(tonumber)

  parser:argument("model", "Model filename"):args("?")
  local parsedArgs = parser:parse(arg)

  parsedArgs.mesher = parsedArgs.mesher or "surface-splatting"

  if parsedArgs.mesher ~= "dual-contouring" and parsedArgs.mesher ~= "surface-splatting" then
    print("Error: argument for option '--mesher' must be one of 'dual-contouring', 'surface-splatting'")
    love.event.quit(1)
    return
  end

  -- Disabled in conf.lua to avoid window flicker on early exit
  require('love.window')

  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    fullscreen = parsedArgs.fullscreen,
    highdpi = parsedArgs.high_dpi,

    minwidth = 800,
    minheight = 600,

    msaa = parsedArgs.msaa,
    resizable = true,
  })

  love.graphics.setBackgroundColor(0.125, 0.125, 0.125, 1)

  editor = Editor.new({}, parsedArgs)

  Slab.SetINIStatePath(nil)
  Slab.Initialize(arg)
end

function love.update(dt)
  editor:update(dt)
end

function love.draw()
  editor:draw()
end

function love.keypressed(key, scancode, isrepeat)
  editor:keypressed(key, scancode, isrepeat)
end

function love.mousemoved(x, y, dx, dy, istouch)
  editor:mousemoved(x, y, dx, dy, istouch)
end

function love.mousepressed(x, y, button, istouch, presses)
  editor:mousepressed(x, y, button, istouch, presses)
end

function love.mousereleased(x, y, button, istouch, presses)
  editor:mousereleased(x, y, button, istouch, presses)
end

function love.threaderror(thread, errorstr)
  print("Thread error: " .. errorstr)
end

function love.wheelmoved(x, y)
  editor:wheelmoved(x, y)
end
