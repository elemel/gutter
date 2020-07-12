local dualContouring = require("gutter.dualContouring")
local dualContouring2 = require("gutter.dualContouring2")
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

      vertices = dualContouring.newMeshFromEdits(input.edits, grid)
    elseif input.mesher == "dual-contouring-2" then
      local grid = dualContouring2.newGrid(
        input.sizeX, input.sizeY, input.sizeZ,
        input.minX, input.minY, input.minZ, input.maxX, input.maxY, input.maxZ)

      vertices = dualContouring2.newMeshFromEdits(input.edits, grid)
    else
      vertices, vertexMap = surfaceSplatting.newMeshFromEdits(
        input.edits,
        input.minX, input.minY, input.minZ, input.maxX, input.maxY, input.maxZ,
        input.sizeX, input.sizeY, input.sizeZ)
    end

    outputChannel:push({vertices = vertices, vertexMap = vertexMap})
  end
end

main(...)
