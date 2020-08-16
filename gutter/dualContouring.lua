local csg = require("gutter.csg")
local gutterMath = require("gutter.math")
local loveMath = require("love.math")
local quaternion = require("gutter.quaternion")

local abs = math.abs
local acos = math.acos
local box = csg.box
local clamp = gutterMath.clamp
local cos = math.cos
local cross = gutterMath.cross
local distance3 = gutterMath.distance3
local dot3 = gutterMath.dot3
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
local pi = math.pi
local smoothSubtractionColor = csg.smoothSubtractionColor
local smoothUnionColor = csg.smoothUnionColor
local smoothstep = gutterMath.smoothstep
local sphere = csg.sphere
local squaredDistance3 = gutterMath.squaredDistance3
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

    minX = minX,
    minY = minY,
    minZ = minZ,

    maxX = maxX,
    maxY = maxY,
    maxZ = maxZ,
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
  local cells = {}

  for z = 1, sizeZ do
    local layer = {}

    for y = 1, sizeY do
      local row = {}

      for x = 1, sizeX do
        row[x] = {
          x = 0,
          y = 0,
          z = 0,

          normalX = 0,
          normalY = 0,
          normalZ = 0,

          red = 0,
          green = 0,
          blue = 0,
          alpha = 0,
        }
      end

      layer[y] = row
    end

    cells[z] = layer
  end

  grid.cells = cells
  return grid
end

function M.applyInstructions(instructions, grid)
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
    local positionX, positionY, positionZ = unpack(instruction.position)
    local qx, qy, qz, qw = unpack(instruction.orientation)

    local instructionRed, instructionGreen, instructionBlue, instructionAlpha = unpack(instruction.color)
    local width, height, depth, rounding = unpack(instruction.shape)
    local maxRadius = 0.5 * min(width, height, depth)
    local radius = rounding * maxRadius
    local blendRange = instruction.blending * maxRadius

    for vertexZ, layer in ipairs(vertices) do
      for vertexY, row in ipairs(layer) do
        for vertexX, vertex in ipairs(row) do
          local instructionX, instructionY, instructionZ = inverseRotate(
            qx, qy, qz, qw,
            vertex.x - positionX, vertex.y - positionY, vertex.z - positionZ)

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
end

function M.updateCells(instructions, grid)
  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  local minX = grid.minX
  local minY = grid.minY
  local minZ = grid.minZ

  local maxX = grid.maxX
  local maxY = grid.maxY
  local maxZ = grid.maxZ

  local dx = 0.25 * (maxX - minX) / sizeX
  local dy = 0.25 * (maxY - minY) / sizeY
  local dz = 0.25 * (maxZ - minZ) / sizeZ

  local vertices = grid.vertices
  local cells = grid.cells

  for cellZ = 1, sizeZ do
    for cellY = 1, sizeY do
      for cellX = 1, sizeX do
        local cell = cells[cellZ][cellY][cellX]

        local totalX = 0
        local totalY = 0
        local totalZ = 0

        local totalRed = 0
        local totalGreen = 0
        local totalBlue = 0
        local totalAlpha = 0

        local count = 0

        for vertexZ = 0, 1 do
          for vertexY = 0, 1 do
            for vertexX = 0, 1 do
              local vertex = vertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

              for vertexZ2 = 0, 1 do
                for vertexY2 = 0, 1 do
                  for vertexX2 = 0, 1 do
                    local vertex2 = vertices[cellZ + vertexZ2][cellY + vertexY2][cellX + vertexX2]

                    if (vertex.distance < 0) ~= (vertex2.distance < 0) then
                      local t = abs(vertex.distance) / (abs(vertex.distance) + abs(vertex2.distance))

                      totalX = totalX + mix(vertex.x, vertex2.x, t)
                      totalY = totalY + mix(vertex.y, vertex2.y, t)
                      totalZ = totalZ + mix(vertex.z, vertex2.z, t)

                      totalRed = totalRed + mix(vertex.red, vertex2.red, t)
                      totalGreen = totalGreen + mix(vertex.green, vertex2.green, t)
                      totalBlue = totalBlue + mix(vertex.blue, vertex2.blue, t)
                      totalAlpha = totalAlpha + mix(vertex.alpha, vertex2.alpha, t)

                      count = count + 1
                    end
                  end
                end
              end
            end
          end
        end

        if count >= 1 then
          cell.x = totalX / count
          cell.y = totalY / count
          cell.z = totalZ / count

          cell.x = totalX / count
          cell.y = totalY / count
          cell.z = totalZ / count

          -- local gradientX = 0
          -- local gradientY = 0
          -- local gradientZ = 0

          -- for vertexZ = 0, 1 do
          --   for vertexY = 0, 1 do
          --     for vertexX = 0, 1 do
          --       local vertex = grid.vertices[cellZ + vertexZ][cellY + vertexY][cellX + vertexX]

          --       gradientX = gradientX + (2 * vertexX - 1) * vertex.distance
          --       gradientY = gradientY + (2 * vertexY - 1) * vertex.distance
          --       gradientZ = gradientZ + (2 * vertexZ - 1) * vertex.distance
          --     end
          --   end
          -- end

          local gradientX, gradientY, gradientZ = csg.getDistanceGradientFromPoint(instructions, cell.x, cell.y, cell.z, dx, dy, dz)

          cell.normalX, cell.normalY, cell.normalZ = normalize3(
            gradientX, gradientY, gradientZ)

          cell.red = totalRed / count
          cell.green = totalGreen / count
          cell.blue = totalBlue / count
          cell.alpha = totalAlpha / count
        end
      end
    end
  end
end

function M.generateTriangle(grid, insideX, insideY, insideZ, outsideX, outsideY, outsideZ, triangles)
  local edgeX = min(insideX, outsideX)
  local edgeY = min(insideY, outsideY)
  local edgeZ = min(insideZ, outsideZ)

  local cells = grid.cells
  local quadCells

  if insideX ~= outsideX then
    quadCells = {
      cells[edgeZ + 0][edgeY + 0][edgeX],
      cells[edgeZ + 0][edgeY - 1][edgeX],
      cells[edgeZ - 1][edgeY - 1][edgeX],
      cells[edgeZ - 1][edgeY + 0][edgeX],
    }
  elseif insideY ~= outsideY then
    quadCells = {
      cells[edgeZ + 0][edgeY][edgeX + 0],
      cells[edgeZ - 1][edgeY][edgeX + 0],
      cells[edgeZ - 1][edgeY][edgeX - 1],
      cells[edgeZ + 0][edgeY][edgeX - 1],
    }
  else
    quadCells = {
      cells[edgeZ][edgeY + 0][edgeX + 0],
      cells[edgeZ][edgeY + 0][edgeX - 1],
      cells[edgeZ][edgeY - 1][edgeX - 1],
      cells[edgeZ][edgeY - 1][edgeX + 0],
    }
  end

  -- Split quad along shortest diagonal
  if squaredDistance3(quadCells[2].x, quadCells[2].y, quadCells[2].z, quadCells[4].x, quadCells[4].y, quadCells[4].z) <
    squaredDistance3(quadCells[1].x, quadCells[1].y, quadCells[1].z, quadCells[3].x, quadCells[3].y, quadCells[3].z) then

    quadCells[1], quadCells[2], quadCells[3], quadCells[4] = quadCells[2], quadCells[3], quadCells[4], quadCells[1]
  end

  -- Fix triangle winding
  if insideX + insideY + insideZ < outsideX + outsideY + outsideZ then
    quadCells[2], quadCells[4] = quadCells[4], quadCells[2]
  end

  -- Generate triangle vertices
  for _, i in ipairs({1, 2, 3, 1, 3, 4}) do
    local cell = quadCells[i]

    table.insert(triangles, {
      cell.x, cell.y, cell.z,
      cell.normalX, cell.normalY, cell.normalZ,
      cell.red, cell.green, cell.blue, cell.alpha,
    })
  end
end

function M.generateTriangles(grid, triangles)
  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  local vertices = grid.vertices

  for edgeZ = 2, sizeZ do
    for edgeY = 2, sizeY do
      for edgeX = 1, sizeX do
        local distance1 = vertices[edgeZ][edgeY][edgeX + 0].distance
        local distance2 = vertices[edgeZ][edgeY][edgeX + 1].distance

        if (distance1 < 0) ~= (distance2 < 0) then
          if distance1 < 0 then
            M.generateTriangle(grid, edgeX, edgeY, edgeZ, edgeX + 1, edgeY, edgeZ, triangles)
          else
            M.generateTriangle(grid, edgeX + 1, edgeY, edgeZ, edgeX, edgeY, edgeZ, triangles)
          end
        end
      end
    end
  end

  for edgeZ = 2, sizeZ do
    for edgeY = 1, sizeY do
      for edgeX = 2, sizeX do
        local distance1 = vertices[edgeZ][edgeY + 0][edgeX].distance
        local distance2 = vertices[edgeZ][edgeY + 1][edgeX].distance

        if (distance1 < 0) ~= (distance2 < 0) then
          if distance1 < 0 then
            M.generateTriangle(grid, edgeX, edgeY, edgeZ, edgeX, edgeY + 1, edgeZ, triangles)
          else
            M.generateTriangle(grid, edgeX, edgeY + 1, edgeZ, edgeX, edgeY, edgeZ, triangles)
          end
        end
      end
    end
  end

  for edgeZ = 1, sizeZ do
    for edgeY = 2, sizeY do
      for edgeX = 2, sizeX do
        local distance1 = vertices[edgeZ + 0][edgeY][edgeX].distance
        local distance2 = vertices[edgeZ + 1][edgeY][edgeX].distance

        if (distance1 < 0) ~= (distance2 < 0) then
          if distance1 < 0 then
            M.generateTriangle(grid, edgeX, edgeY, edgeZ, edgeX, edgeY, edgeZ + 1, triangles)
          else
            M.generateTriangle(grid, edgeX, edgeY, edgeZ + 1, edgeX, edgeY, edgeZ, triangles)
          end
        end
      end
    end
  end

  return triangles
end

function M.newMeshFromInstructions(instructions, bounds, maxCallDepth, callDepth, triangles)
  callDepth = callDepth or 0
  triangles = triangles or {}

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
    return triangles
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
          }, maxCallDepth, callDepth + 1, triangles)
        end
      end
    end

    return triangles
  end

  local extendedBounds = {
    minX = minX - 0.5 * (maxX - minX),
    minY = minY - 0.5 * (maxY - minY),
    minZ = minZ - 0.5 * (maxZ - minZ),

    maxX = maxX,
    maxY = maxY,
    maxZ = maxZ,

    -- maxX = maxX + 0.5 * (maxX - minX),
    -- maxY = maxY + 0.5 * (maxY - minY),
    -- maxZ = maxZ + 0.5 * (maxZ - minZ),
  }

  local grid = M.newGrid({3, 3, 3}, extendedBounds)

  M.applyInstructions(instructions, grid)
  M.updateCells(instructions, grid)
  M.generateTriangles(grid, triangles)

  return triangles
end

function M.fixTriangleNormals(triangles, maxAlignmentAngle)
  maxAlignmentAngle = maxAlignmentAngle or 0.25 * pi
  local minAlignment = cos(maxAlignmentAngle)

  for i = 1, #triangles, 3 do
    local x1 = triangles[i + 0][1]
    local y1 = triangles[i + 0][2]
    local z1 = triangles[i + 0][3]

    local x2 = triangles[i + 1][1]
    local y2 = triangles[i + 1][2]
    local z2 = triangles[i + 1][3]

    local x3 = triangles[i + 2][1]
    local y3 = triangles[i + 2][2]
    local z3 = triangles[i + 2][3]

    local faceNormalX, faceNormalY, faceNormalZ = normalize3(cross(
      x3 - x1, y3 - y1, z3 - z1, x2 - x1, y2 - y1, z2 - z1))

    for j = i, i + 2 do
      local vertex = triangles[j]

      local alignment = dot3(
        vertex[4], vertex[5], vertex[6],
        faceNormalX, faceNormalY, faceNormalZ)

      if alignment < minAlignment then
        local t = maxAlignmentAngle / acos(alignment)

        vertex[4], vertex[5], vertex[6] = normalize3(mix3(
          vertex[4], vertex[5], vertex[6],
          faceNormalX, faceNormalY, faceNormalZ,
          1 - t))
      end
    end
  end
end

return M
