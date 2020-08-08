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
      local bounds = {
        minX = input.minX,
        minY = input.minY,
        minZ = input.minZ,

        maxX = input.maxX,
        maxY = input.maxY,
        maxZ = input.maxZ,
      }

      vertices = dualContouring.newMeshFromInstructions(input.instructions, bounds, input.maxDepth)
      dualContouring.fixTriangleNormals(vertices)
    else
      local bounds = {
        minX = input.minX,
        minY = input.minY,
        minZ = input.minZ,

        maxX = input.maxX,
        maxY = input.maxY,
        maxZ = input.maxZ,
      }

      vertices, vertexMap = surfaceSplatting.newMeshFromInstructions(
        input.instructions, bounds, input.maxDepth)
    end

    outputChannel:push({
      version = input.version,
      vertices = vertices,
      vertexMap = vertexMap,
    })
  end
end

main(...)
