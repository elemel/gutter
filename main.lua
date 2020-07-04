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

local function length3(x, y, z)
  return math.sqrt(x * x + y * y + z * z)
end

local function mix3(ax, ay, az, bx, by, bz, t)
  local x = (1 - t) * ax + t * bx
  local y = (1 - t) * ay + t * by
  local z = (1 - t) * az + t * bz

  return x, y, z
end

local function unitSphere(x, y, z)
  return length3(x, y, z) - 1
end

local function normal(x, y, z, epsilon, distance)
  local dx = distance(x + epsilon, y, z) - distance(x - epsilon, y, z)
  local dy = distance(x, y + epsilon, z) - distance(x, y - epsilon, z)
  local dz = distance(x, y, z + epsilon) - distance(x, y, z - epsilon)

  return normalize3(dx, dy, dz)
end

local function surface(ax, ay, az, bx, by, bz, distance)
  local ad = distance(ax, ay, az)
  local bd = distance(bx, by, bz)

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

  points = {}
  vertices = {}
  vertexMap = {}

  local r = 0.25

  local ax = -1
  local ay = -1
  local az = -1

  local bx = 1
  local by = 1
  local bz = 1

  local nx = 8
  local ny = 8
  local nz = 8

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

        local hit, sx, sy, sz = surface(cx, dy, dz, ex, dy, dz, unitSphere)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz
        end

        local hit, sx, sy, sz = surface(dx, cy, dz, dx, ey, dz, unitSphere)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz
        end

        local hit, sx, sy, sz = surface(dx, dy, cz, dx, dy, ez, unitSphere)

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

    local nx, ny, nz = normal(x, y, z, 0.5 * r, unitSphere)
    local tx, ty, tz = perp3(nx, ny, nz)
    local bx, by, bz = cross3(tx, ty, tz, nx, ny, nz)

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
  local r = 0.25

  for i, point in ipairs(points) do
    local x, y, z = unpack(point)

    if z < 0 then
      local nx, ny, nz = normal(x, y, z, 0.5 * r, unitSphere)
      love.graphics.setColor(0, 0.5, 1, 1)
      love.graphics.line(x, y, x + vectorScale * nx, y + vectorScale * ny)

      local tx, ty, tz = perp3(nx, ny, nz)
      love.graphics.setColor(1, 0.25, 0, 1)
      love.graphics.line(x, y, x + vectorScale * tx, y + vectorScale * ty)

      local bx, by, bz = cross3(tx, ty, tz, nx, ny, nz)
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
