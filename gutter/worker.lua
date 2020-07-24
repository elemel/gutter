local dualContouring = require("gutter.dualContouring")
local surfaceSplatting = require("gutter.surfaceSplatting")

local function main(arg)
  local inputChannel = love.thread.getChannel("workerInput")
  local outputChannel = love.thread.getChannel("workerOutput")

  while true do
    local input = inputChannel:demand()

    if input == "quit" then
      break
    end

    local vertices, vertexMap

    if input.mesher == "dual-contouring" then
      local grid = dualContouring.newGrid(
        input.sizeX, input.sizeY, input.sizeZ,
        input.minX, input.minY, input.minZ, input.maxX, input.maxY, input.maxZ)

      vertices = dualContouring.newMeshFromInstructions(input.instructions, grid)
    else
      local bounds = {
        minX = input.minX,
        minY = input.minY,
        minZ = input.minZ,

        maxX = input.maxX,
        maxY = input.maxY,
        maxZ = input.maxZ,
      }

      local gridSize = {input.sizeX, input.sizeY, input.sizeZ}

      vertices, vertexMap = surfaceSplatting.newMeshFromInstructions(
        input.instructions, bounds, gridSize)
    end

    outputChannel:push({vertices = vertices, vertexMap = vertexMap})
  end
end

main(...)
