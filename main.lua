local math1 = require("math1")
local math3 = require("math3")

local clamp = math1.clamp
local cross = math3.cross
local length3 = math3.length
local mix = math1.mix
local mix3 = math3.mix
local normalize3 = math3.normalize
local perp3 = math3.perp
local transformPoint3 = math3.transformPoint

-- https://www.iquilezles.org/www/articles/smin/smin.htm
local function smoothUnion(a, b, k)
  local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
  return mix(b, a, h) - k * h * (1 - h)
end

local function smoothSubtraction(d1, d2, k)
  local h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0, 1)
  return mix(d2, -d1, h) + k * h * (1 - h)
end

local function sphere(x, y, z, r)
  return length3(x, y, z) - r
end

local function sculptureDistance(sculpture, x, y, z)
  local distance = 1e9

  for i, edit in ipairs(sculpture.edits) do
    local ex, ey, ez = transformPoint3(edit.inverseTransform, x, y, z)
    local editDistance

    if edit.brush == "sphere" then
      editDistance = sphere(ex, ey, ez, edit.scale)
    else
      assert("Invalid brush")
    end

    if edit.operation == "union" then
      distance = smoothUnion(distance, editDistance, edit.smoothRadius)
    elseif edit.operation == "subtract" then
      distance = smoothSubtraction(distance, editDistance, edit.smoothRadius)
    else
      assert("Invalid operation")
    end
  end

  return distance
end

local function sculptureNormal(sculpture, x, y, z, epsilon)
  local dx = sculptureDistance(sculpture, x + epsilon, y, z) - sculptureDistance(sculpture, x - epsilon, y, z)
  local dy = sculptureDistance(sculpture, x, y + epsilon, z) - sculptureDistance(sculpture, x, y - epsilon, z)
  local dz = sculptureDistance(sculpture, x, y, z + epsilon) - sculptureDistance(sculpture, x, y, z - epsilon)

  return normalize3(dx, dy, dz)
end

local function sculptureSurface(sculpture, ax, ay, az, bx, by, bz)
  local ad = sculptureDistance(sculpture, ax, ay, az)
  local bd = sculptureDistance(sculpture, bx, by, bz)

  if ad * bd > 0 then
    return false
  end

  local t = math.abs(ad) / (math.abs(ad) + math.abs(bd))
  return true, mix3(ax, ay, az, bx, by, bz, t)
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

  local sculpture = {
    edits = {
      {
        operation = "union",
        brush = "sphere",
        inverseTransform = love.math.newTransform(-0.5, -0.25):inverse(),
        scale = 0.5,
        smoothRadius = 0,
      },

      {
        operation = "union",
        brush = "sphere",
        inverseTransform = love.math.newTransform(0.5, 0.25):inverse(),
        scale = 0.75,
        smoothRadius = 0.5,
      },
    }
  }

  points = {}
  vertices = {}
  vertexMap = {}

  local r = 0.125

  local ax = -2
  local ay = -1
  local az = -1

  local bx = 2
  local by = 1
  local bz = 1

  local nx = 32
  local ny = 16
  local nz = 16

  for ix = 1, nx do
    local cx = ax + (ix - 1) / nx * (bx - ax)
    local ex = ax + ix / nx * (bx - ax)
    local dx = 0.5 * (cx + ex)

    for iy = 1, ny do
      local cy = ay + (iy - 1) / ny * (by - ay)
      local ey = ay + iy / ny * (by - ay)
      local dy = 0.5 * (cy + ey)

      for iz = 1, nz do
        local cz = az + (iz - 1) / nz * (bz - az)
        local ez = az + iz / nz * (bz - az)
        local dz = 0.5 * (cz + ez)

        local hitCount = 0

        local totalSx = 0
        local totalSy = 0
        local totalSz = 0

        local hit, sx, sy, sz = sculptureSurface(sculpture, cx, dy, dz, ex, dy, dz)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz
        end

        local hit, sx, sy, sz = sculptureSurface(sculpture, dx, cy, dz, dx, ey, dz)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz
        end

        local hit, sx, sy, sz = sculptureSurface(sculpture, dx, dy, cz, dx, dy, ez)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz
        end

        if hitCount >= 1 then
          table.insert(points, {
            totalSx / hitCount,
            totalSy / hitCount,
            totalSz / hitCount,
          })
        end
      end
    end
  end

  for _, point in ipairs(points) do
    local x, y, z = unpack(point)

    local nx, ny, nz = sculptureNormal(sculpture, x, y, z, 0.5 * r)
    local tx, ty, tz = perp3(nx, ny, nz)
    local bx, by, bz = cross(tx, ty, tz, nx, ny, nz)

    table.insert(point, nx)
    table.insert(point, ny)
    table.insert(point, nz)

    table.insert(vertices, {
      x - r * tx - r * bx,
      y - r * ty - r * by,
      z - r * tz - r * bz,

      nx, ny, nz,
      -1, -1,
      1, 0.25, 0, 1,
    })

    table.insert(vertices, {
      x + r * tx - r * bx,
      y + r * ty - r * by,
      z + r * tz - r * bz,

      nx, ny, nz,
      1, -1,
      1, 1, 0, 1,
    })

    table.insert(vertices, {
      x + r * tx + r * bx,
      y + r * ty + r * by,
      z + r * tz + r * bz,

      nx, ny, nz,
      1, 1,
      0, 1, 0, 1,
    })

    table.insert(vertices, {
      x - r * tx + r * bx,
      y - r * ty + r * by,
      z - r * tz + r * bz,

      nx, ny, nz,
      -1, 1,
      0, 0.5, 1, 1,
    })

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 2)
    table.insert(vertexMap, #vertices - 1)

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 1)
    table.insert(vertexMap, #vertices)
  end

  local vertexFormat = {
    {"VertexPosition", "float", 3},
    {"VertexNormal", "float", 3},
    {"VertexTexCoord", "float", 2},
    {"VertexColor", "byte", 4},
  }

  mesh = love.graphics.newMesh(vertexFormat, vertices, "triangles")
  mesh:setVertexMap(vertexMap)
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
  love.graphics.setMeshCullMode("back")
  love.graphics.setDepthMode("less", true)
  love.graphics.draw(mesh)
  love.graphics.setDepthMode()
  love.graphics.setMeshCullMode("none")
  love.graphics.setShader(nil)

  local vectorScale = 0.25
  local r = 0.125

  for i, point in ipairs(points) do
    local x, y, z, nx, ny, nz = unpack(point)

    if z < 0 then
      love.graphics.setColor(0, 0.5, 1, 1)
      love.graphics.line(x, y, x + vectorScale * nx, y + vectorScale * ny)

      local tx, ty, tz = perp3(nx, ny, nz)
      love.graphics.setColor(1, 0.25, 0, 1)
      love.graphics.line(x, y, x + vectorScale * tx, y + vectorScale * ty)

      local bx, by, bz = cross(tx, ty, tz, nx, ny, nz)
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
