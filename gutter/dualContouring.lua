local csg = require("gutter.csg")
local gutterMath = require("gutter.math")
local loveMath = require("love.math")

local acos = math.acos
local box = csg.box
local cos = math.cos
local cross = gutterMath.cross
local dot3 = gutterMath.dot3
local fbm3 = gutterMath.fbm3
local huge = math.huge
local min = math.min
local mix = gutterMath.mix
local mix3 = gutterMath.mix3
local mix4 = gutterMath.mix4
local noise = loveMath.noise
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

function M.newGrid(sizeX, sizeY, sizeZ, minX, minY, minZ, maxX, maxY, maxZ)
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

function M.applyEdits(edits, grid)
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

  for _, edit in ipairs(edits) do
    local editRed, editGreen, editBlue, editAlpha = unpack(edit.color)

    local noiseConfig = edit.noise
    local noiseFrequency = noiseConfig.frequency or 1
    local noiseAmplitude = noiseConfig.amplitude or 1
    local noiseOctaves = noiseConfig.octaves or 0
    local noiseLacunarity = noiseConfig.lacunarity or 2
    local noiseGain = noiseConfig.gain or 0.5

    for vertexZ, layer in ipairs(vertices) do
      local z = mix(minZ, maxZ, (vertexZ - 1) / sizeX)

      for vertexY, row in ipairs(layer) do
        local y = mix(minY, maxY, (vertexY - 1) / sizeY)

        for vertexX, vertex in ipairs(row) do
          local x = mix(minX, maxX, (vertexX - 1) / sizeZ)

          local editX, editY, editZ = transformPoint3(edit.inverseTransform, x, y, z)
          local editDistance

          if edit.primitive == "box" then
            editDistance = box(editX, editY, editZ, edit.scale, edit.scale, edit.scale)
          elseif edit.primitive == "sphere" then
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
          elseif edit.operation == "subtraction" then
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
end

function M.updateCells(grid)
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
  local cells = grid.cells

  for cellZ = 1, sizeZ do
    for cellY = 1, sizeY do
      for cellX = 1, sizeX do
        local cell = cells[cellZ][cellY][cellX]

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

          local x, y, z = mix3(
            insideX, insideY, insideZ,
            outsideX, outsideY, outsideZ,
            -insideDistance / (outsideDistance - insideDistance))

          cell.x = mix(minX, maxX, (cellX - 1 + x) / sizeX)
          cell.y = mix(minY, maxY, (cellY - 1 + y) / sizeY)
          cell.z = mix(minZ, maxZ, (cellZ - 1 + z) / sizeZ)

          local distance000 = vertices[cellZ + 0][cellY + 0][cellX + 0].distance
          local distance001 = vertices[cellZ + 0][cellY + 0][cellX + 1].distance
          local distance010 = vertices[cellZ + 0][cellY + 1][cellX + 0].distance
          local distance011 = vertices[cellZ + 0][cellY + 1][cellX + 1].distance
          local distance100 = vertices[cellZ + 1][cellY + 0][cellX + 0].distance
          local distance101 = vertices[cellZ + 1][cellY + 0][cellX + 1].distance
          local distance110 = vertices[cellZ + 1][cellY + 1][cellX + 0].distance
          local distance111 = vertices[cellZ + 1][cellY + 1][cellX + 1].distance

          local gradientX = mix(
            mix(distance001 - distance000, distance011 - distance010, y),
            mix(distance101 - distance100, distance111 - distance110, y),
            z)

          local gradientY = mix(
            mix(distance010 - distance000, distance011 - distance001, x),
            mix(distance110 - distance100, distance111 - distance101, x),
            z)

          local gradientZ = mix(
            mix(distance100 - distance000, distance101 - distance001, x),
            mix(distance110 - distance010, distance111 - distance011, x),
            y)

          cell.normalX, cell.normalY, cell.normalZ = normalize3(
            gradientX, gradientY, gradientZ)

          cell.red, cell.green, cell.blue, cell.alpha = mix4(
            insideRed, insideGreen, insideBlue, insideAlpha,
            outsideRed, outsideGreen, outsideBlue, outsideAlpha,
            -insideDistance / (outsideDistance - insideDistance))
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

function M.generateTriangles(grid)
  local sizeX = grid.sizeX
  local sizeY = grid.sizeY
  local sizeZ = grid.sizeZ

  local vertices = grid.vertices
  local triangles = {}

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

function M.newMeshFromEdits(edits, grid)
  M.applyEdits(edits, grid)
  M.updateCells(grid)
  local triangles = M.generateTriangles(grid)

  local maxAlignmentAngle = 1 / 16 * pi
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

  return triangles
end

return M
