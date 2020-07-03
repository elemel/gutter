local function normalize3(x, y, z)
  local length = math.sqrt(x * x + y * y + z * z)
  return x / length, y / length, z / length
end

-- https://math.stackexchange.com/a/1586011
local function randomPointOnUnitSphere(random)
  random = random or love.math.random

  while true do
    local x = 2 * random() - 1
    local y = 2 * random() - 1
    local z = 2 * random() - 1

    if x * x + y * y + z * z < 1 then
      return normalize3(x, y, z)
    end
  end
end

local function perp3(x, y, z)
  if math.abs(x) < math.abs(y) then
    if math.abs(y) < math.abs(z) then
      return 0, -z, y
    elseif math.abs(x) < math.abs(z) then
      return 0, z, -y
    else
      return -y, x, 0
    end
  else
    if math.abs(z) < math.abs(y) then
      return y, -x, 0
    elseif math.abs(z) < math.abs(x) then
      return z, 0, -x
    else
      return -z, 0, x
    end
  end
end

local function cross3(ax, ay, az, bx, by, bz)
  return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

function love.load(arg)
  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    -- highdpi = true,
    resizable = true,
  })

  shader = love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
    {
      if (dot(texture_coords, texture_coords) > 1) {
        discard;
      }

      return color;
    }
  ]])

  points = {}
  vertices = {}
  vertexMap = {}

  for _ = 1, 256 do
    local x, y, z = randomPointOnUnitSphere()

    table.insert(points, x)
    table.insert(points, y)
    table.insert(points, z)

    local nx, ny, nz = normalize3(x, y, z)
    local tx, ty, tz = perp3(nx, ny, nz)
    local bx, by, bz = cross3(nx, ny, nz, tx, ty, tz)

    local r = 0.1

    table.insert(vertices, {x - r * tx - r * bx, y - r * ty - r * by, -1, -1, 1, 0.25, 0, 1})
    table.insert(vertices, {x + r * tx - r * bx, y + r * ty - r * by, 1, -1, 1, 1, 0, 1})
    table.insert(vertices, {x + r * tx + r * bx, y + r * ty + r * by, 1, 1, 0, 1, 0, 1})
    table.insert(vertices, {x - r * tx + r * bx, y - r * ty + r * by, -1, 1, 0, 0.5, 1, 1})

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 2)
    table.insert(vertexMap, #vertices - 1)

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 1)
    table.insert(vertexMap, #vertices)
  end

  mesh = love.graphics.newMesh(vertices, "triangles")
  mesh:setVertexMap(vertexMap)
end

function love.draw()
  local width, height = love.graphics.getDimensions()
  love.graphics.translate(0.5 * width, 0.5 * height)

  local scale = 0.375 * height
  love.graphics.scale(scale)
  love.graphics.setLineWidth(1 / scale)

  love.graphics.rotate(0.25 * love.timer.getTime())

  -- love.graphics.setColor(1, 1, 1, 0.5)
  -- love.graphics.draw(mesh)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  love.graphics.draw(mesh)
  love.graphics.setShader(nil)

  local vectorScale = 0.25

  for i = 1, #points, 3 do
    local x = points[i]
    local y = points[i + 1]
    local z = points[i + 2]

    if z < 0 then
      local nx, ny, nz = normalize3(x, y, z)
      love.graphics.setColor(0, 0.5, 1, 1)
      love.graphics.line(x, y, x + vectorScale * nx, y + vectorScale * ny)

      local tx, ty, tz = perp3(nx, ny, nz)
      love.graphics.setColor(1, 0.25, 0, 1)
      love.graphics.line(x, y, x + vectorScale * tx, y + vectorScale * ty)

      local bx, by, bz = cross3(nx, ny, nz, tx, ty, tz)
      love.graphics.setColor(0, 1, 0, 1)
      love.graphics.line(x, y, x + vectorScale * bx, y + vectorScale * by)
    end
  end
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
