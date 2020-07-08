local gutterMath = require("gutter.math")
local surfaceSplatting = require("gutter.surfaceSplatting")

local translate3 = gutterMath.translate3

function love.load(arg)
  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    highdpi = true,
    resizable = true,
  })

  shader = love.graphics.newShader([[
    varying vec3 VaryingNormal;

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
      if (dot(texture_coords, texture_coords) > 1) {
        discard;
      }

      vec3 normal = normalize(VaryingNormal);
      vec3 sunLighting = dot(normalize(vec3(-2, -8, 4)), normal) * 3 * vec3(1, 0.5, 0.25);
      vec3 skyLighting = 1 * vec3(0.25, 0.5, 1);
      vec3 lighting = sunLighting + skyLighting;
      return vec4(lighting, 1) * color;
    }
  ]], [[
    uniform mat3 MyNormalMatrix;
    attribute vec3 VertexNormal;
    attribute vec3 DiskCenter;
    varying vec3 VaryingNormal;

    vec4 position( mat4 transform_projection, vec4 vertex_position )
    {
      VaryingNormal = MyNormalMatrix * VertexNormal;
      vec4 result = transform_projection * vertex_position;
      result.z = (transform_projection * vec4(DiskCenter, 1)).z;
      return result;
    }
  ]])

  local sculpture = {
    edits = {
      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(-0.5, -0.25):inverse(),
        scale = 0.5,
        smoothRadius = 0,
        color = {0.5, 1, 0.25, 1},
      },

      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(0.5, 0.25):inverse(),
        scale = 0.75,
        smoothRadius = 0.5,
        color = {0.25, 0.75, 1, 1},
      },

      {
        operation = "subtract",
        primitive = "sphere",
        inverseTransform = translate3(love.math.newTransform(), 0, -0.25, 0.5):inverse(),
        scale = 0.5,
        smoothRadius = 0.25,
        color = {1, 0.5, 0.25, 1},
      },
    }
  }

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

  local sizeX = 128
  local sizeY = 128
  local sizeZ = 128

  local time = love.timer.getTime()

  mesh, points = surfaceSplatting.newMeshFromEdits(
    sculpture.edits, minX, minY, minZ, maxX, maxY, maxZ, sizeX, sizeY, sizeZ)

  time = love.timer.getTime() - time
  print(string.format("Total: Converted model to mesh in %.3f seconds", time))
end

function love.draw()
  local width, height = love.graphics.getDimensions()
  love.graphics.translate(0.5 * width, 0.5 * height)

  local scale = 0.375 * height
  love.graphics.scale(scale)
  love.graphics.setLineWidth(1 / scale)

  -- love.graphics.rotate(0.25 * love.timer.getTime())

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  shader:send("MyNormalMatrix", {1, 0, 0, 0, 1, 0, 0, 0, 1})
  love.graphics.setMeshCullMode("back")
  love.graphics.setDepthMode("less", true)
  love.graphics.draw(mesh)
  love.graphics.setDepthMode()
  love.graphics.setMeshCullMode("none")
  love.graphics.setShader(nil)

  -- surfaceSplatting.debugDrawPointBases(points)
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
