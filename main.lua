function love.load(arg)
  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    highdpi = true,
    resizable = true,
  })

  local vertices = {
    {2, 0, 2, 0, 1, 0, 0, 1},
    {-1, 1.7320508075688774, -1, 1.7320508075688774, 0, 1, 0, 1},
    {-1, -1.7320508075688774, -1, -1.7320508075688774, 0, 0, 1, 1},
  }

  mesh = love.graphics.newMesh(vertices, triangles)

  shader = love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
      if (texture_coords.x * texture_coords.x + texture_coords.y * texture_coords.y > 1 * 1) {
        discard;
      }

      return color;
    }
  ]])
end

function love.draw()
  local width, height = love.graphics.getDimensions()
  love.graphics.translate(0.5 * width, 0.5 * height)
  love.graphics.scale(0.25 * height)
  love.graphics.rotate(love.timer.getTime())

  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.draw(mesh)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  love.graphics.draw(mesh)
  love.graphics.setShader(nil)
end

function love.keypressed(key, scancode, isrepeat)
  if key == "1" then
    local timestamp = os.date('%Y-%m-%d-%H-%M-%S')
    local filename = "screenshot-" .. timestamp .. ".png"
    love.graphics.captureScreenshot(filename)

    local directory = love.filesystem.getSaveDirectory()
    print("Captured screenshot: " .. directory .. "/" .. filename)
  end
end
