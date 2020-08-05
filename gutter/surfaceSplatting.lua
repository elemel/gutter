local csg = require("gutter.csg")
local gutterMath = require("gutter.math")
local loveMath = require("love.math")
local lton = require("lton")
local quaternion = require("gutter.quaternion")

local abs = math.abs
local box = csg.box
local cross = gutterMath.cross
local distance3 = gutterMath.distance3
local dump = lton.dump
local fbm3 = gutterMath.fbm3
local huge = math.huge
local inverseRotate = quaternion.inverseRotate
local max = math.max
local min = math.min
local mix = gutterMath.mix
local mix3 = gutterMath.mix3
local mix4 = gutterMath.mix4
local normalize3 = gutterMath.normalize3
local perp = gutterMath.perp
local smoothSubtractionColor = csg.smoothSubtractionColor
local smoothUnionColor = csg.smoothUnionColor
local sphere = csg.sphere
local transformPoint3 = gutterMath.transformPoint3

local M = {}

function M.newGrid(size, bounds)
  local sizeX, sizeY, sizeZ = unpack(size)

  local minX = bounds.minX
  local minY = bounds.minY
  local minZ = bounds.minZ

  local maxX = bounds.maxX
  local maxY = bounds.maxY
  local maxZ = bounds.maxZ

  local grid = {
    sizeX = sizeX,
    sizeY = sizeY,
    sizeZ = sizeZ,

    minX = bounds.minX,
    minY = bounds.minY,
    minZ = bounds.minZ,

    maxX = bounds.maxX,
    maxY = bounds.maxY,
    maxZ = bounds.maxZ,
  }

  local vertices = {}

  for z = 1, sizeZ + 1 do
    local layer = {}

    for y = 1, sizeY + 1 do
      local row = {}

      for x = 1, sizeX + 1 do
        row[x] = {
          x = mix(minX, maxX, (x - 1) / sizeX),
          y = mix(minY, maxY, (y - 1) / sizeY),
          z = mix(minZ, maxZ, (z - 1) / sizeZ),

          distance = huge,

          red = 0,
          green = 0,
          blue = 0,
          alpha = 0,
        }
      end

      layer[y] = row
    end

    vertices[z] = layer
  end

  grid.vertices = vertices

  return grid
end

function M.getInstructionDistanceAndBlendRangeForPoint(instruction, x, y, z)
  local positionX, positionY, positionZ = unpack(instruction.position)
  local qx, qy, qz, qw = unpack(instruction.orientation)

  local instructionRed, instructionGreen, instructionBlue, instructionAlpha = unpack(instruction.color)
  local width, height, depth, rounding = unpack(instruction.shape)
  local maxRadius = 0.5 * min(width, height, depth)
  local radius = rounding * maxRadius
  local blendRange = instruction.blending * maxRadius

  local instructionX, instructionY, instructionZ = inverseRotate(
    qx, qy, qz, qw, x - positionX, y - positionY, z - positionZ)

  local instructionDistance = box(
    instructionX, instructionY, instructionZ,
    0.5 * width - radius, 0.5 * height - radius, 0.5 * depth - radius) - radius

  return instructionDistance, blendRange
end

function M.applyInstructionToGrid(instruction, grid)
  local positionX, positionY, positionZ = unpack(instruction.position)
  local qx, qy, qz, qw = unpack(instruction.orientation)

  local instructionRed, instructionGreen, instructionBlue, instructionAlpha = unpack(instruction.color)
  local width, height, depth, rounding = unpack(instruction.shape)
  local maxRadius = 0.5 * min(width, height, depth)
  local radius = rounding * maxRadius
  local blendRange = instruction.blending * maxRadius

  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  local minX = grid.minX
  local minY = grid.minY
  local minZ = grid.minZ

  local maxX = grid.maxX
  local maxY = grid.maxY
  local maxZ = grid.maxZ

  for vertexZ, layer in ipairs(grid.vertices) do
    for vertexY, row in ipairs(layer) do
      for vertexX, vertex in ipairs(row) do
        local instructionX, instructionY, instructionZ = inverseRotate(
          qx, qy, qz, qw, vertex.x - positionX, vertex.y - positionY, vertex.z - positionZ)

        local instructionDistance = box(
          instructionX, instructionY, instructionZ,
          0.5 * width - radius, 0.5 * height - radius, 0.5 * depth - radius) - radius

        if instruction.operation == "union" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothUnionColor(
              vertex.distance,
              vertex.red, vertex.green, vertex.blue, vertex.alpha,
              instructionDistance, instructionRed, instructionGreen, instructionBlue, instructionAlpha, blendRange)
        elseif instruction.operation == "subtraction" then
          vertex.distance, vertex.red, vertex.green, vertex.blue, vertex.alpha =
            smoothSubtractionColor(
              instructionDistance, instructionRed, instructionGreen, instructionBlue, instructionAlpha,
              vertex.distance,
              vertex.red, vertex.green, vertex.blue, vertex.alpha,
              blendRange)
        else
          assert("Invalid operation")
        end
      end
    end
  end
end

function M.newMeshFromInstructions(instructions, bounds, gridSize)
  local grid = M.newGrid(gridSize, bounds)

  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  local minX = grid.minX
  local minY = grid.minY
  local minZ = grid.minZ

  local maxX = grid.maxX
  local maxY = grid.maxY
  local maxZ = grid.maxZ

  local vertices = grid.vertices

  for _, instruction in ipairs(instructions) do
    M.applyInstructionToGrid(instruction, grid)
  end

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
              local vertex = vertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

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

          local distance000 = vertices[cellZ + 0][cellY + 0][cellX + 0].distance
          local distance001 = vertices[cellZ + 0][cellY + 0][cellX + 1].distance
          local distance010 = vertices[cellZ + 0][cellY + 1][cellX + 0].distance
          local distance011 = vertices[cellZ + 0][cellY + 1][cellX + 1].distance
          local distance100 = vertices[cellZ + 1][cellY + 0][cellX + 0].distance
          local distance101 = vertices[cellZ + 1][cellY + 0][cellX + 1].distance
          local distance110 = vertices[cellZ + 1][cellY + 1][cellX + 0].distance
          local distance111 = vertices[cellZ + 1][cellY + 1][cellX + 1].distance

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
    })

    table.insert(vertices, {
      x + radiusX * tangentX - radiusX * bitangentX,
      y + radiusY * tangentY - radiusY * bitangentY,
      z + radiusZ * tangentZ - radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, -1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x + radiusX * tangentX + radiusX * bitangentX,
      y + radiusY * tangentY + radiusY * bitangentY,
      z + radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, 1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x - radiusX * tangentX + radiusX * bitangentX,
      y - radiusY * tangentY + radiusY * bitangentY,
      z - radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      -1, 1,
      red, green, blue, alpha,
    })

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 2)
    table.insert(vertexMap, #vertices - 1)

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 1)
    table.insert(vertexMap, #vertices)
  end

  return vertices, vertexMap
end

function M.newMeshFromInstructions2(instructions, bounds, maxCallDepth, callDepth, vertices, vertexMap, disks)
  callDepth = callDepth or 0
  vertices = vertices or {}
  vertexMap = vertexMap or {}
  disks = disks or {}

  local minX = bounds.minX
  local minY = bounds.minY
  local minZ = bounds.minZ

  local maxX = bounds.maxX
  local maxY = bounds.maxY
  local maxZ = bounds.maxZ

  local midX = 0.5 * (bounds.minX + bounds.maxX)
  local midY = 0.5 * (bounds.minY + bounds.maxY)
  local midZ = 0.5 * (bounds.minZ + bounds.maxZ)

  local filteredInstructions = {}
  local maxBlendRange = 0
  local maxDistance = distance3(midX, midY, midZ, bounds.maxX, bounds.maxY, bounds.maxZ)

  for i = #instructions, 1, -1 do
    local distance, blendRange = M.getInstructionDistanceAndBlendRangeForPoint(instructions[i], midX, midY, midZ)

    if distance - blendRange < maxDistance + maxBlendRange then
      table.insert(filteredInstructions, 1, instructions[i])
      maxBlendRange = max(maxBlendRange, blendRange)
    end
  end

  while #filteredInstructions > 0 and filteredInstructions[1].operation == "subtraction" do
    table.remove(filteredInstructions, 1)
  end

  if #filteredInstructions == 0 then
    return vertices, vertexMap, disks
  end

  if callDepth < maxCallDepth then
    for z = 1, 2 do
      for y = 1, 2 do
        for x = 1, 2 do
          M.newMeshFromInstructions2(filteredInstructions, {
            minX = mix(minX, maxX, (x - 1) / 2),
            minY = mix(minY, maxY, (y - 1) / 2),
            minZ = mix(minZ, maxZ, (z - 1) / 2),

            maxX = mix(minX, maxX, x / 2),
            maxY = mix(minY, maxY, y / 2),
            maxZ = mix(minZ, maxZ, z / 2),
          }, maxCallDepth, callDepth + 1, vertices, vertexMap, disks)
        end
      end
    end

    return vertices, vertexMap, disks
  end

  local grid = M.newGrid({2, 2, 2}, bounds)
  local localDisks = {}

  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  for _, instruction in ipairs(filteredInstructions) do
    M.applyInstructionToGrid(instruction, grid)
  end

  local gridVertices = grid.vertices

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
              local vertex = gridVertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

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

          local distance000 = gridVertices[cellZ + 0][cellY + 0][cellX + 0].distance
          local distance001 = gridVertices[cellZ + 0][cellY + 0][cellX + 1].distance
          local distance010 = gridVertices[cellZ + 0][cellY + 1][cellX + 0].distance
          local distance011 = gridVertices[cellZ + 0][cellY + 1][cellX + 1].distance
          local distance100 = gridVertices[cellZ + 1][cellY + 0][cellX + 0].distance
          local distance101 = gridVertices[cellZ + 1][cellY + 0][cellX + 1].distance
          local distance110 = gridVertices[cellZ + 1][cellY + 1][cellX + 0].distance
          local distance111 = gridVertices[cellZ + 1][cellY + 1][cellX + 1].distance

          local gradX = mix(mix(distance001 - distance000, distance011 - distance010, fractionY), mix(distance101 - distance100, distance111 - distance110, fractionY), fractionZ)
          local gradY = mix(mix(distance010 - distance000, distance011 - distance001, fractionX), mix(distance110 - distance100, distance111 - distance101, fractionX), fractionZ)
          local gradZ = mix(mix(distance100 - distance000, distance101 - distance001, fractionX), mix(distance110 - distance010, distance111 - distance011, fractionX), fractionY)

          local normalX, normalY, normalZ = normalize3(gradX, gradY, gradZ)
          local red, green, blue, alpha = mix4(insideRed, insideGreen, insideBlue, insideAlpha, outsideRed, outsideGreen, outsideBlue, outsideAlpha, -insideDistance / (outsideDistance - insideDistance))

          local disk = {x, y, z, normalX, normalY, normalZ, red, green, blue, alpha}
          table.insert(localDisks, disk)
          table.insert(disks, disk)
        end
      end
    end
  end

  local radiusX = (maxX - minX) / sizeX
  local radiusY = (maxY - minY) / sizeY
  local radiusZ = (maxZ - minZ) / sizeZ

  for _, disk in ipairs(localDisks) do
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
    })

    table.insert(vertices, {
      x + radiusX * tangentX - radiusX * bitangentX,
      y + radiusY * tangentY - radiusY * bitangentY,
      z + radiusZ * tangentZ - radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, -1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x + radiusX * tangentX + radiusX * bitangentX,
      y + radiusY * tangentY + radiusY * bitangentY,
      z + radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, 1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x - radiusX * tangentX + radiusX * bitangentX,
      y - radiusY * tangentY + radiusY * bitangentY,
      z - radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      -1, 1,
      red, green, blue, alpha,
    })

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 2)
    table.insert(vertexMap, #vertices - 1)

    table.insert(vertexMap, #vertices - 3)
    table.insert(vertexMap, #vertices - 1)
    table.insert(vertexMap, #vertices)
  end

  return vertices, vertexMap, disks
end

-- function M.debugDrawDiskBases(disks)
--   local vectorScale = 0.25

--   for _, disk in ipairs(disks) do
--     local x, y, z, normalX, normalY, normalZ, red, green, blue, alpha = unpack(disk)

--     if z < 0 then
--       love.graphics.setColor(0, 0.5, 1, 1)
--       love.graphics.line(x, y, x + vectorScale * normalX, y + vectorScale * normalY)

--       local tangentX, tangentY, tangentZ = perp(normalX, normalY, normalZ)
--       love.graphics.setColor(1, 0.25, 0, 1)
--       love.graphics.line(x, y, x + vectorScale * tangentX, y + vectorScale * tangentY)

--       local bitangentX, bitangentY, bitangentZ = cross(tangentX, tangentY, tangentZ, normalY, normalY, normalZ)
--       love.graphics.setColor(0, 1, 0, 1)
--       love.graphics.line(x, y, x + vectorScale * bitangentX, y + vectorScale * bitangentY)
--     end
--   end
-- end

return M
