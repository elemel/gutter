local csg = require("gutter.csg")
local gutterMath = require("gutter.math")

local cross = gutterMath.cross
local fbm3 = gutterMath.fbm3
local mix = gutterMath.mix
local mix3 = gutterMath.mix3
local mix4 = gutterMath.mix4
local noise = love.math.noise
local normalize3 = gutterMath.normalize3
local perp = gutterMath.perp
local smoothSubtractionColor = csg.smoothSubtractionColor
local smoothUnionColor = csg.smoothUnionColor
local sphere = csg.sphere
local transformPoint3 = gutterMath.transformPoint3

local M = {}

function M.newGrid(sizeX, sizeY, sizeZ)
  local grid = {}

  for z = 1, sizeZ do
    local layer = {}

    for y = 1, sizeY do
      local row = {}

      for x = 1, sizeX do
        row[x] = {
          distance = math.huge,

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

function M.applyEditToGrid(edit, minX, minY, minZ, maxX, maxY, maxZ, grid)
  local editRed, editGreen, editBlue, editAlpha = unpack(edit.color)

  local noiseConfig = edit.noise
  local noiseFrequency = noiseConfig.frequency or 1
  local noiseAmplitude = noiseConfig.amplitude or 1
  local noiseOctaves = noiseConfig.octaves or 0
  local noiseLacunarity = noiseConfig.lacunarity or 2
  local noiseGain = noiseConfig.gain or 0.5

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

        if noiseOctaves > 0 then
          editDistance = editDistance + noiseAmplitude * (2 * fbm3(
            noiseFrequency * x,
            noiseFrequency * y,
            noiseFrequency * z,
            noise,
            noiseOctaves,
            noiseLacunarity,
            noiseGain) - 1)
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

function M.newMeshFromEdits(edits, minX, minY, minZ, maxX, maxY, maxZ, sizeX, sizeY, sizeZ)
  local gridTime = love.timer.getTime()

  -- We need an extra vertex after the last cell
  local grid = M.newGrid(sizeX + 1, sizeY + 1, sizeZ + 1)

  gridTime = love.timer.getTime() - gridTime
  print(string.format("Initialized %d x %d x %d grid in %.3f seconds", sizeX, sizeY, sizeZ, gridTime))

  local editTime = love.timer.getTime()

  for _, edit in ipairs(edits) do
    M.applyEditToGrid(edit, minX, minY, minZ, maxX, maxY, maxZ, grid)
  end

  editTime = love.timer.getTime() - editTime
  print(string.format("Appled %d edits in %.3f seconds", #edits, editTime))

  local diskTime = love.timer.getTime()
  local disks = {}

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

          local disk = {x, y, z, normalX, normalY, normalZ, red, green, blue, alpha}
          table.insert(disks, disk)
        end
      end
    end
  end

  diskTime = love.timer.getTime() - diskTime
  print(string.format("Generated %d disks in %.3f seconds", #disks, diskTime))

  local meshTime = love.timer.getTime()

  local vertices = {}
  local vertexMap = {}

  local radiusX = (maxX - minX) / sizeX
  local radiusY = (maxY - minY) / sizeY
  local radiusZ = (maxZ - minZ) / sizeZ

  for _, disk in ipairs(disks) do
    local x, y, z, normalX, normalY, normalZ, red, green, blue, alpha = unpack(disk)

    local tangentX, tangentY, tangentZ = perp(normalX, normalY, normalZ)
    local bitangentX, bitangentY, bitangentZ = cross(tangentX, tangentY, tangentZ, normalX, normalY, normalZ)

    table.insert(vertices, {
      x - radiusX * tangentX - radiusX * bitangentX,
      y - radiusY * tangentY - radiusY * bitangentY,
      z - radiusZ * tangentZ - radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      -1, -1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x + radiusX * tangentX - radiusX * bitangentX,
      y + radiusY * tangentY - radiusY * bitangentY,
      z + radiusZ * tangentZ - radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, -1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x + radiusX * tangentX + radiusX * bitangentX,
      y + radiusY * tangentY + radiusY * bitangentY,
      z + radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, 1,
      red, green, blue, alpha,
      x, y, z,
    })

    table.insert(vertices, {
      x - radiusX * tangentX + radiusX * bitangentX,
      y - radiusY * tangentY + radiusY * bitangentY,
      z - radiusZ * tangentZ + radiusZ * bitangentZ,

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

  return mesh, disks
end

function M.debugDrawDiskBases(disks)
  local vectorScale = 0.25

  for _, disk in ipairs(disks) do
    local x, y, z, normalX, normalY, normalZ, red, green, blue, alpha = unpack(disk)

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

return M
