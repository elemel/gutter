local gutterMath = require("gutter.math")

local clamp = gutterMath.clamp
local cross = gutterMath.cross
local length3 = gutterMath.length3
local mix = gutterMath.mix
local mix3 = gutterMath.mix3
local mix4 = gutterMath.mix4
local normalize3 = gutterMath.normalize3
local perp = gutterMath.perp
local translate3 = gutterMath.translate3
local transformPoint3 = gutterMath.transformPoint3

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

local function sphere(x, y, z, radius)
  return length3(x, y, z) - radius
end

local function newGrid(sizeX, sizeY, sizeZ)
  local grid = {}

  for z = 1, sizeZ do
    local layer = {}

    for y = 1, sizeY do
      local row = {}

      for x = 1, sizeX do
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

local function applyEditToGrid(edit, minX, minY, minZ, maxX, maxY, maxZ, grid)
  local editRed, editGreen, editBlue, editAlpha = unpack(edit.color)

  for vertexZ, layer in ipairs(grid) do
    local z = mix(minZ, maxZ, (vertexZ - 1) / (#grid - 1))

    for vertexY, row in ipairs(layer) do
      local y = mix(minY, maxY, (vertexY - 1) / (#layer - 1))

      for vertexX, vertex in ipairs(row) do
        local x = mix(minX, maxX, (vertexX - 1) / (#row - 1))

        local editX, editY, editZ = transformPoint3(edit.inverseTransform, x, y, z)
        local editDistance

        if edit.primitive == "sphere" then
          editDistance = sphere(editX, editY, editZ, edit.scale)
        else
          assert("Invalid primitive")
        end

        if edit.operation == "union" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothUnionColor(
              vertex.distance,
              vertex.red, vertex.green, vertex.blue, vertex.alpha,
              editDistance, editRed, editGreen, editBlue, editAlpha, edit.smoothRadius)
        elseif edit.operation == "subtract" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothSubtractionColor(
              editDistance, editRed, editGreen, editBlue, editAlpha,
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

local function newMeshFromEdits(edits, minX, minY, minZ, maxX, maxY, maxZ, sizeX, sizeY, sizeZ)
  local gridTime = love.timer.getTime()

  -- We need an extra vertex after the last cell
  local grid = newGrid(sizeX + 1, sizeY + 1, sizeZ + 1)

  gridTime = love.timer.getTime() - gridTime
  print(string.format("Initialized %dx%dx%d grid in %.3f seconds", sizeX, sizeY, sizeZ, gridTime))

  local editTime = love.timer.getTime()

  for _, edit in ipairs(edits) do
    applyEditToGrid(edit, minX, minY, minZ, maxX, maxY, maxZ, grid)
  end

  editTime = love.timer.getTime() - editTime
  print(string.format("Appled %d edits in %.3f seconds", #edits, editTime))

  local pointTime = love.timer.getTime()

  -- TODO: Make local. Currently global for debug drawing.
  points = {}

  for cellZ = 1, sizeZ do
    for cellY = 1, sizeY do
      for cellX = 1, sizeX do
        local insideCount = 0
        local insideDistance = 0

        local insideX = 0
        local insideY = 0
        local insideZ = 0

        local insideRed = 0
        local insideGreen = 0
        local insideBlue = 0
        local insideAlpha = 0

        local outsideCount = 0
        local outsideDistance = 0

        local outsideX = 0
        local outsideY = 0
        local outsideZ = 0

        local outsideRed = 0
        local outsideGreen = 0
        local outsideBlue = 0
        local outsideAlpha = 0

        for vertexZ = 0, 1 do
          for vertexY = 0, 1 do
            for vertexX = 0, 1 do
              local vertex = grid[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

              if vertex.distance < 0 then
                insideCount = insideCount + 1
                insideDistance = insideDistance + vertex.distance

                insideX = insideX + vertexX
                insideY = insideY + vertexY
                insideZ = insideZ + vertexZ

                insideRed = insideRed + vertex.red
                insideGreen = insideGreen + vertex.green
                insideBlue = insideBlue + vertex.blue
                insideAlpha = insideAlpha + vertex.alpha
              else
                outsideCount = outsideCount + 1
                outsideDistance = outsideDistance + vertex.distance

                outsideX = outsideX + vertexX
                outsideY = outsideY + vertexY
                outsideZ = outsideZ + vertexZ

                outsideRed = outsideRed + vertex.red
                outsideGreen = outsideGreen + vertex.green
                outsideBlue = outsideBlue + vertex.blue
                outsideAlpha = outsideAlpha + vertex.alpha
              end
            end
          end
        end

        if insideCount >= 1 and outsideCount >= 1 then
          insideDistance = insideDistance / insideCount

          insideX = insideX / insideCount
          insideY = insideY / insideCount
          insideZ = insideZ / insideCount

          insideRed = insideRed / insideCount
          insideGreen = insideGreen / insideCount
          insideBlue = insideBlue / insideCount
          insideAlpha = insideAlpha / insideCount

          outsideDistance = outsideDistance / outsideCount

          outsideX = outsideX / outsideCount
          outsideY = outsideY / outsideCount
          outsideZ = outsideZ / outsideCount

          outsideRed = outsideRed / outsideCount
          outsideGreen = outsideGreen / outsideCount
          outsideBlue = outsideBlue / outsideCount
          outsideAlpha = outsideAlpha / outsideCount

          local fractionX, fractionY, fractionZ = mix3(insideX, insideY, insideZ, outsideX, outsideY, outsideZ, -insideDistance / (outsideDistance - insideDistance))

          local x = mix(minX, maxX, (cellX - 1 + fractionX) / sizeX)
          local y = mix(minY, maxY, (cellY - 1 + fractionY) / sizeY)
          local z = mix(minZ, maxZ, (cellZ - 1 + fractionZ) / sizeZ)

          local distance000 = grid[cellZ + 0][cellY + 0][cellX + 0].distance
          local distance001 = grid[cellZ + 0][cellY + 0][cellX + 1].distance
          local distance010 = grid[cellZ + 0][cellY + 1][cellX + 0].distance
          local distance011 = grid[cellZ + 0][cellY + 1][cellX + 1].distance
          local distance100 = grid[cellZ + 1][cellY + 0][cellX + 0].distance
          local distance101 = grid[cellZ + 1][cellY + 0][cellX + 1].distance
          local distance110 = grid[cellZ + 1][cellY + 1][cellX + 0].distance
          local distance111 = grid[cellZ + 1][cellY + 1][cellX + 1].distance

          local gradX = mix(mix(distance001 - distance000, distance011 - distance010, fractionY), mix(distance101 - distance100, distance111 - distance110, fractionY), fractionZ)
          local gradY = mix(mix(distance010 - distance000, distance011 - distance001, fractionX), mix(distance110 - distance100, distance111 - distance101, fractionX), fractionZ)
          local gradZ = mix(mix(distance100 - distance000, distance101 - distance001, fractionX), mix(distance110 - distance010, distance111 - distance011, fractionX), fractionY)

          local normalX, normalY, normalZ = normalize3(gradX, gradY, gradZ)
          local red, green, blue, alpha = mix4(insideRed, insideGreen, insideBlue, insideAlpha, outsideRed, outsideGreen, outsideBlue, outsideAlpha, -insideDistance / (outsideDistance - insideDistance))

          local point = {x, y, z, normalX, normalY, normalZ, red, green, blue, alpha}
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
  local diskRadius = (maxX - minX) / sizeX -- TODO: Per-axis radius?

  for _, point in ipairs(points) do
    local x, y, z, normalX, normalY, normalZ, red, green, blue, alpha = unpack(point)

    local tangentX, tangentY, tangentZ = perp(normalX, normalY, normalZ)
    local bitangentX, bitangentY, bitangentZ = cross(tangentX, tangentY, tangentZ, normalX, normalY, normalZ)

    table.insert(point, normalX)
    table.insert(point, normalY)
    table.insert(point, normalZ)

    table.insert(vertices, {
      x - diskRadius * tangentX - diskRadius * bitangentX,
      y - diskRadius * tangentY - diskRadius * bitangentY,
      z - diskRadius * tangentZ - diskRadius * bitangentZ,

      normalX, normalY, normalZ,
      -1, -1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x + diskRadius * tangentX - diskRadius * bitangentX,
      y + diskRadius * tangentY - diskRadius * bitangentY,
      z + diskRadius * tangentZ - diskRadius * bitangentZ,

      normalX, normalY, normalZ,
      1, -1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x + diskRadius * tangentX + diskRadius * bitangentX,
      y + diskRadius * tangentY + diskRadius * bitangentY,
      z + diskRadius * tangentZ + diskRadius * bitangentZ,

      normalX, normalY, normalZ,
      1, 1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x - diskRadius * tangentX + diskRadius * bitangentX,
      y - diskRadius * tangentY + diskRadius * bitangentY,
      z - diskRadius * tangentZ + diskRadius * bitangentZ,

      normalX, normalY, normalZ,
      -1, 1,
      red, green, blue, alpha,
      x, y, z,
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
    {"DiskCenter", "float", 3},
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
  mesh = newMeshFromEdits(sculpture.edits, minX, minY, minZ, maxX, maxY, maxZ, sizeX, sizeY, sizeZ)
  time = love.timer.getTime() - time
  print(string.format("Total: Converted model to mesh in %.3f seconds.", time))
end

local function debugDrawPointBases(points)
  local vectorScale = 0.25

  for _, point in ipairs(points) do
    local x, y, z, normalX, normalY, normalZ, red, green, blue, alpha = unpack(point)

    if z < 0 then
      love.graphics.setColor(0, 0.5, 1, 1)
      love.graphics.line(x, y, x + vectorScale * normalX, y + vectorScale * normalY)

      local tangentX, tangentY, tangentZ = perp(normalX, normalY, normalZ)
      love.graphics.setColor(1, 0.25, 0, 1)
      love.graphics.line(x, y, x + vectorScale * tangentX, y + vectorScale * tangentY)

      local bitangentX, bitangentY, bitangentZ = cross(tangentX, tangentY, tangentZ, normalY, normalY, normalZ)
      love.graphics.setColor(0, 1, 0, 1)
      love.graphics.line(x, y, x + vectorScale * bitangentX, y + vectorScale * bitangentY)
    end
  end
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

  -- debugDrawPointBases(points)
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
