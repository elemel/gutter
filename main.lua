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

local function newGrid(nx, ny, nz)
  local grid = {}

  for z = 1, nz do
    local layer = {}

    for y = 1, ny do
      local row = {}

      for x = 1, nx do
        row[x] = {
          distance = 1e9,

          red = 0,
          green = 0,
          blue = 0,
          alpha = 0,
        }
      end

      layer[y] = row
    end

    grid[z] = layer
  end

  return grid
end

local function applyEditToGrid(edit, ax, ay, az, bx, by, bz, grid)
  local er, eg, eb, ea = unpack(edit.color)

  for iz, layer in ipairs(grid) do
    local z = mix(az, bz, (iz - 1) / (#grid - 1))

    for iy, row in ipairs(layer) do
      local y = mix(ay, by, (iy - 1) / (#layer - 1))

      for ix, vertex in ipairs(row) do
        local x = mix(ax, bx, (ix - 1) / (#row - 1))

        local ex, ey, ez = transformPoint3(edit.inverseTransform, x, y, z)
        local ed

        if edit.primitive == "sphere" then
          ed = sphere(ex, ey, ez, edit.scale)
        else
          assert("Invalid primitive")
        end

        if edit.operation == "union" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothUnionColor(
              vertex.distance,
              vertex.red, vertex.green, vertex.blue, vertex.alpha,
              ed, er, eg, eb, ea, edit.smoothRadius)
        elseif edit.operation == "subtract" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothSubtractionColor(
              ed, er, eg, eb, ea,
              vertex.distance,
              vertex.red, vertex.green, vertex.blue, vertex.alpha,
              edit.smoothRadius)
        else
          assert("Invalid operation")
        end
      end
    end
  end
end

local function newMeshFromEdits(edits, ax, ay, az, bx, by, bz, nx, ny, nz)
  local gridTime = love.timer.getTime()

  -- We need an extra vertex after the last cell
  local grid = newGrid(nx + 1, ny + 1, nz + 1)

  gridTime = love.timer.getTime() - gridTime
  print(string.format("Initialized %dx%dx%d grid in %.3f seconds", nx, ny, nz, gridTime))

  local editTime = love.timer.getTime()

  for _, edit in ipairs(edits) do
    applyEditToGrid(edit, ax, ay, az, bx, by, bz, grid)
  end

  editTime = love.timer.getTime() - editTime

  print(string.format("Appled %d edits in %.3f seconds", #edits, editTime))

  local pointTime = love.timer.getTime()

  local points = {}

  for cz = 1, nz do
    for cy = 1, ny do
      for cx = 1, nx do
        local in_ = 0
        local id = 0

        local ix = 0
        local iy = 0
        local iz = 0

        local ir = 0
        local ig = 0
        local ib = 0
        local ia = 0

        local on = 0
        local od = 0

        local ox = 0
        local oy = 0
        local oz = 0

        local or_ = 0
        local og = 0
        local ob = 0
        local oa = 0

        for vz = 0, 1 do
          for vy = 0, 1 do
            for vx = 0, 1 do
              local vertex = grid[cz + vz][cy + vy][cx + vx]

              if vertex.distance < 0 then
                in_ = in_ + 1
                id = id + vertex.distance

                ix = ix + vx
                iy = iy + vy
                iz = iz + vz

                ir = ir + vertex.red
                ig = ig + vertex.green
                ib = ib + vertex.blue
                ia = ia + vertex.alpha
              else
                on = on + 1
                od = od + vertex.distance

                ox = ox + vx
                oy = oy + vy
                oz = oz + vz

                or_ = or_ + vertex.red
                og = og + vertex.green
                ob = ob + vertex.blue
                oa = oa + vertex.alpha
              end
            end
          end
        end

        if in_ >= 1 and on >= 1 then
          id = id / in_

          ix = ix / in_
          iy = iy / in_
          iz = iz / in_

          ir = ir / in_
          ig = ig / in_
          ib = ib / in_
          ia = ia / in_

          od = od / on

          ox = ox / on
          oy = oy / on
          oz = oz / on

          or_ = or_ / on
          og = og / on
          ob = ob / on
          oa = oa / on

          local fx, fy, fz = mix3(ix, iy, iz, ox, oy, oz, -id / (od - id))

          local x = mix(ax, bx, (cx - 1 + fx) / nx)
          local y = mix(ay, by, (cy - 1 + fy) / ny)
          local z = mix(az, bz, (cz - 1 + fz) / nz)

          local d000 = grid[cz + 0][cy + 0][cx + 0].distance
          local d001 = grid[cz + 0][cy + 0][cx + 1].distance
          local d010 = grid[cz + 0][cy + 1][cx + 0].distance
          local d011 = grid[cz + 0][cy + 1][cx + 1].distance
          local d100 = grid[cz + 1][cy + 0][cx + 0].distance
          local d101 = grid[cz + 1][cy + 0][cx + 1].distance
          local d110 = grid[cz + 1][cy + 1][cx + 0].distance
          local d111 = grid[cz + 1][cy + 1][cx + 1].distance

          local gradX = mix(mix(d001 - d000, d011 - d010, fy), mix(d101 - d100, d111 - d110, fy), fz)
          local gradY = mix(mix(d010 - d000, d011 - d001, fx), mix(d110 - d100, d111 - d101, fx), fz)
          local gradZ = mix(mix(d100 - d000, d101 - d001, fx), mix(d110 - d010, d111 - d011, fx), fy)

          local normalX, normalY, normalZ = normalize3(gradX, gradY, gradZ)
          local r, g, b, a = mix4(ir, ig, ib, ia, or_, og, ob, oa, -id / (od - id))

          local point = {x, y, z, normalX, normalY, normalZ, r, g, b, a}
          table.insert(points, point)
        end
      end
    end
  end

  pointTime = love.timer.getTime() - pointTime
  print(string.format("Generated %d points in %.3f seconds", #points, pointTime))

  local meshTime = love.timer.getTime()

  local vertices = {}
  local vertexMap = {}
  local dr = (bx - ax) / nx -- TODO: Per-axis radius?

  for _, point in ipairs(points) do
    local x, y, z, nx, ny, nz, r, g, b, a = unpack(point)

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

  meshTime = love.timer.getTime() - meshTime
  print(string.format("Created mesh in %.3f seconds", meshTime))

  return mesh
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
        smoothRadius = 0,
        color = {0.25, 1, 0.125, 1},
      },

      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(0.5, 0.25):inverse(),
        scale = 0.75,
        smoothRadius = 0.5,
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
  local ay = -2
  local az = -2

  local bx = 2
  local by = 2
  local bz = 2

  local nx = 128
  local ny = 128
  local nz = 128

  mesh = newMeshFromEdits(sculpture.edits, ax, ay, az, bx, by, bz, nx, ny, nz)
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
