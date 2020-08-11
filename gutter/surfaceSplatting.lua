local csg = require("gutter.csg")
local gutterMath = require("gutter.math")
local loveMath = require("love.math")
local lton = require("lton")
local quaternion = require("gutter.quaternion")

local abs = math.abs
local box = csg.box
local clamp = gutterMath.clamp
local cross = gutterMath.cross
local distance3 = gutterMath.distance3
local dump = lton.dump
local fbm3 = gutterMath.fbm3
local getInstructionDistanceAndBlendRangeForPoint = csg.getInstructionDistanceAndBlendRangeForPoint
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

function M.newMeshFromInstructions(instructions, bounds, maxCallDepth, callDepth, vertices, vertexMap)
  callDepth = callDepth or 0
  vertices = vertices or {}
  vertexMap = vertexMap or {}

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
    local distance, blendRange = getInstructionDistanceAndBlendRangeForPoint(instructions[i], midX, midY, midZ)

    if distance - blendRange < maxDistance + maxBlendRange then
      table.insert(filteredInstructions, 1, instructions[i])
      maxBlendRange = max(maxBlendRange, blendRange)
    end
  end

  while #filteredInstructions > 0 and filteredInstructions[1].operation == "subtraction" do
    table.remove(filteredInstructions, 1)
  end

  if #filteredInstructions == 0 then
    return vertices, vertexMap
  end

  if callDepth < maxCallDepth then
    for z = 1, 2 do
      for y = 1, 2 do
        for x = 1, 2 do
          M.newMeshFromInstructions(filteredInstructions, {
            minX = mix(minX, maxX, (x - 1) / 2),
            minY = mix(minY, maxY, (y - 1) / 2),
            minZ = mix(minZ, maxZ, (z - 1) / 2),

            maxX = mix(minX, maxX, x / 2),
            maxY = mix(minY, maxY, y / 2),
            maxZ = mix(minZ, maxZ, z / 2),
          }, maxCallDepth, callDepth + 1, vertices, vertexMap)
        end
      end
    end

    return vertices, vertexMap
  end

  local grid = M.newGrid({2, 2, 2}, bounds)

  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  for _, instruction in ipairs(filteredInstructions) do
    M.applyInstructionToGrid(instruction, grid)
  end

  local gridVertices = grid.vertices
  local disks = {}

  for cellZ = 1, sizeZ do
    for cellY = 1, sizeY do
      for cellX = 1, sizeX do
        local sign = 0

        for vertexZ = 0, 1 do
          for vertexY = 0, 1 do
            for vertexX = 0, 1 do
              local vertex = gridVertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]
              sign = sign + (vertex.distance < 0 and -1 or 1)
            end
          end
        end

        if sign ~= -8 and sign ~= 8 then
          local distance = 0

          local red = 0
          local green = 0
          local blue = 0
          local alpha = 0

          local gradientX = 0
          local gradientY = 0
          local gradientZ = 0

          for vertexZ = 0, 1 do
            for vertexY = 0, 1 do
              for vertexX = 0, 1 do
                local vertex = gridVertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

                distance = distance + vertex.distance / 8

                red = red + vertex.red / 8
                green = green + vertex.green / 8
                blue = blue + vertex.blue / 8
                alpha = alpha + vertex.alpha / 8

                gradientX = gradientX + (2 * vertexX - 1) * vertex.distance
                gradientY = gradientY + (2 * vertexY - 1) * vertex.distance
                gradientZ = gradientZ + (2 * vertexZ - 1) * vertex.distance
              end
            end
          end

          distance = clamp(distance, -0.5, 0.5)
          local normalX, normalY, normalZ = normalize3(gradientX, gradientY, gradientZ)

          local x = mix(minX, maxX, (cellX - 0.5) / sizeX) - distance * normalX
          local y = mix(minY, maxY, (cellY - 0.5) / sizeY) - distance * normalY
          local z = mix(minZ, maxZ, (cellZ - 0.5) / sizeZ) - distance * normalZ

          local disk = {x, y, z, normalX, normalY, normalZ, red, green, blue, alpha}
          table.insert(disks, disk)
        end
      end
    end
  end

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
      0, 0, 0, 1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x + radiusX * tangentX - radiusX * bitangentX,
      y + radiusY * tangentY - radiusY * bitangentY,
      z + radiusZ * tangentZ - radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, 0, 0, 1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x + radiusX * tangentX + radiusX * bitangentX,
      y + radiusY * tangentY + radiusY * bitangentY,
      z + radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      1, 1, 0, 1,
      red, green, blue, alpha,
    })

    table.insert(vertices, {
      x - radiusX * tangentX + radiusX * bitangentX,
      y - radiusY * tangentY + radiusY * bitangentY,
      z - radiusZ * tangentZ + radiusZ * bitangentZ,

      normalX, normalY, normalZ,
      0, 1, 0, 1,
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

return M
