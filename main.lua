local math1 = require("math1")
local math3 = require("math3")

local clamp = math1.clamp
local cross = math3.cross
local length3 = math3.length
local mix = math1.mix
local mix3 = math3.mix
local normalize3 = math3.normalize
local perp3 = math3.perp
local translate3 = math3.translate
local transformPoint3 = math3.transformPoint

local function mix4(ax, ay, az, aw, bx, by, bz, bw, t)
  local x = (1 - t) * ax + t * bx
  local y = (1 - t) * ay + t * by
  local z = (1 - t) * az + t * bz
  local w = (1 - t) * aw + t * bw

  return x, y, z, w
end

-- https://www.iquilezles.org/www/articles/smin/smin.htm
local function smoothUnion(a, b, k)
  local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
  return mix(b, a, h) - k * h * (1 - h)
end

local function smoothSubtraction(d1, d2, k)
  local h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0, 1)
  return mix(d2, -d1, h) + k * h * (1 - h)
end

local function smoothstep(x1, x2, x)
    x = clamp((x - x1) / (x2 - x1), 0, 1)
    return x * x * (3 - 2 * x)
end

local function smoothUnionColor(ad, ar, ag, ab, aa, bd, br, bg, bb, ba, k)
  local d = smoothUnion(ad, bd, k)
  local t = smoothstep(-k, k, ad - bd);
  return d, mix4(ar, ag, ab, aa, br, bg, bb, ba, t)
end

local function smoothSubtractionColor(ad, ar, ag, ab, aa, bd, br, bg, bb, ba, k)
  local d = smoothSubtraction(ad, bd, k)
  local t = smoothstep(-k, k, bd + ad);
  return d, mix4(ar, ag, ab, aa, br, bg, bb, ba, t)
end

local function sphere(x, y, z, r)
  return length3(x, y, z) - r
end

local function sculptureDistance(sculpture, x, y, z)
  local distance = 1e9
  local r = 1
  local g = 1
  local b = 1
  local a = 1

  for i, edit in ipairs(sculpture.edits) do
    local ex, ey, ez = transformPoint3(edit.inverseTransform, x, y, z)
    local er, eg, eb, ea = unpack(edit.color)
    local editDistance

    if edit.primitive == "sphere" then
      editDistance = sphere(ex, ey, ez, edit.scale)
    else
      assert("Invalid primitive")
    end

    if edit.operation == "union" then
      distance, r, g, b, a = smoothUnionColor(distance, r, g, b, a, editDistance, er, eg, eb, ea, edit.smoothRadius)
    elseif edit.operation == "subtract" then
      distance, r, g, b, a = smoothSubtractionColor(editDistance, er, eg, eb, ea, distance, r, g, b, a, edit.smoothRadius)
    else
      assert("Invalid operation")
    end
  end

  return distance, r, g, b, a
end

local function sculptureNormal(sculpture, x, y, z, epsilon)
  local dx = sculptureDistance(sculpture, x + epsilon, y, z) - sculptureDistance(sculpture, x - epsilon, y, z)
  local dy = sculptureDistance(sculpture, x, y + epsilon, z) - sculptureDistance(sculpture, x, y - epsilon, z)
  local dz = sculptureDistance(sculpture, x, y, z + epsilon) - sculptureDistance(sculpture, x, y, z - epsilon)

  return normalize3(dx, dy, dz)
end

local function sculptureSurface(sculpture, ax, ay, az, bx, by, bz)
  local ad, ar, ag, ab, aa = sculptureDistance(sculpture, ax, ay, az)
  local bd, br, bg, bb, ba = sculptureDistance(sculpture, bx, by, bz)

  if ad * bd > 0 then
    return false
  end

  local t = math.abs(ad) / (math.abs(ad) + math.abs(bd))

  local x, y, z = mix3(ax, ay, az, bx, by, bz, t)
  local r, g, b, a = mix4(ar, ag, ab, aa, br, bg, bb, ba, t)

  return true, x, y, z, r, g, b, a
end

function love.load(arg)
  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    -- highdpi = true,
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
    varying vec3 VaryingNormal;

    vec4 position( mat4 transform_projection, vec4 vertex_position )
    {
      VaryingNormal = MyNormalMatrix * VertexNormal;
      return transform_projection * vertex_position;
    }
  ]])

  local sculpture = {
    edits = {
      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(-0.5, -0.25):inverse(),
        scale = 0.5,
        smoothRadius = 0.25,
        color = {0.25, 1, 0.125, 1},
      },

      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(0.5, 0.25):inverse(),
        scale = 0.75,
        smoothRadius = 0.55,
        color = {0.125, 0.5, 1, 1},
      },

      {
        operation = "subtract",
        primitive = "sphere",
        inverseTransform = translate3(love.math.newTransform(), 0, -0.25, 0.5):inverse(),
        scale = 0.5,
        smoothRadius = 0.25,
        color = {1, 0.25, 0.125, 1},
      },
    }
  }

  points = {}
  vertices = {}
  vertexMap = {}

  local dr = 0.0625

  local ax = -2
  local ay = -1
  local az = -1

  local bx = 2
  local by = 1
  local bz = 1

  local nx = 64
  local ny = 32
  local nz = 32

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

        local totalR = 0
        local totalG = 0
        local totalB = 0
        local totalA = 0

        local hit, sx, sy, sz, sr, sg, sb, sa = sculptureSurface(sculpture, cx, dy, dz, ex, dy, dz)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz

          totalR = totalR + sr
          totalG = totalG + sg
          totalB = totalB + sb
          totalA = totalA + sa
        end

        local hit, sx, sy, sz, sr, sg, sb, sa = sculptureSurface(sculpture, dx, cy, dz, dx, ey, dz)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz

          totalR = totalR + sr
          totalG = totalG + sg
          totalB = totalB + sb
          totalA = totalA + sa
        end

        local hit, sx, sy, sz, sr, sg, sb, sa = sculptureSurface(sculpture, dx, dy, cz, dx, dy, ez)

        if hit then
          hitCount = hitCount + 1

          totalSx = totalSx + sx
          totalSy = totalSy + sy
          totalSz = totalSz + sz

          totalR = totalR + sr
          totalG = totalG + sg
          totalB = totalB + sb
          totalA = totalA + sa
        end

        if hitCount >= 1 then
          table.insert(points, {
            totalSx / hitCount,
            totalSy / hitCount,
            totalSz / hitCount,

            love.math.linearToGamma(totalR / hitCount,
            totalG / hitCount,
            totalB / hitCount,
            totalA / hitCount),
          })
        end
      end
    end
  end

  for _, point in ipairs(points) do
    local x, y, z, r, g, b, a = unpack(point)

    local nx, ny, nz = sculptureNormal(sculpture, x, y, z, 0.5 * dr)
    local tx, ty, tz = perp3(nx, ny, nz)
    local bx, by, bz = cross(tx, ty, tz, nx, ny, nz)

    table.insert(point, nx)
    table.insert(point, ny)
    table.insert(point, nz)

    table.insert(vertices, {
      x - dr * tx - dr * bx,
      y - dr * ty - dr * by,
      z - dr * tz - dr * bz,

      nx, ny, nz,
      -1, -1,
      r, g, b, a,
    })

    table.insert(vertices, {
      x + dr * tx - dr * bx,
      y + dr * ty - dr * by,
      z + dr * tz - dr * bz,

      nx, ny, nz,
      1, -1,
      r, g, b, a,
    })

    table.insert(vertices, {
      x + dr * tx + dr * bx,
      y + dr * ty + dr * by,
      z + dr * tz + dr * bz,

      nx, ny, nz,
      1, 1,
      r, g, b, a,
    })

    table.insert(vertices, {
      x - dr * tx + dr * bx,
      y - dr * ty + dr * by,
      z - dr * tz + dr * bz,

      nx, ny, nz,
      -1, 1,
      r, g, b, a,
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
  shader:send("MyNormalMatrix", {1, 0, 0, 0, 1, 0, 0, 0, 1})
  love.graphics.setMeshCullMode("back")
  love.graphics.setDepthMode("less", true)
  love.graphics.draw(mesh)
  love.graphics.setDepthMode()
  love.graphics.setMeshCullMode("none")
  love.graphics.setShader(nil)

  local vectorScale = 0.25
  local dr = 0.0625

  -- for i, point in ipairs(points) do
  --   local x, y, z, nx, ny, nz = unpack(point)

  --   if z < 0 then
  --     love.graphics.setColor(0, 0.5, 1, 1)
  --     love.graphics.line(x, y, x + vectorScale * nx, y + vectorScale * ny)

  --     local tx, ty, tz = perp3(nx, ny, nz)
  --     love.graphics.setColor(1, 0.25, 0, 1)
  --     love.graphics.line(x, y, x + vectorScale * tx, y + vectorScale * ty)

  --     local bx, by, bz = cross(tx, ty, tz, nx, ny, nz)
  --     love.graphics.setColor(0, 1, 0, 1)
  --     love.graphics.line(x, y, x + vectorScale * bx, y + vectorScale * by)
  --   end
  -- end
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
