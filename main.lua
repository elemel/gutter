local argparse = require("argparse")
local gutterMath = require("gutter.math")

local floor = math.floor
local pi = math.pi
local setRotation3 = gutterMath.setRotation3
local setTranslation3 = gutterMath.setTranslation3
local transformPoint3 = gutterMath.transformPoint3
local translate3 = gutterMath.translate3

function love.load(arg)
  local parser = argparse("love DIRECTORY", "Mesh and draw a CSG model")
  parser:flag("--editor", "Enable editor mode")
  parser:flag("--fullscreen", "Enable fullscreen mode")
  parser:flag("--high-dpi", "Enable high DPI mode")
  parser:option("--mesher", "Meshing algorithm"):args(1)
  parser:option("--msaa", "Antialiasing samples"):args(1):convert(tonumber)
  local parsedArgs = parser:parse(arg)

  editor = parsedArgs.editor
  mesher = parsedArgs.mesher or "surface-splatting"

  if mesher ~= "dual-contouring" and mesher ~= "dual-contouring-2" and mesher ~= "surface-splatting" then
    print("Error: argument for option '--mesher' must be one of 'dual-contouring', 'dual-contouring-2', 'surface-splatting'")
    love.event.quit(1)
    return
  end

  -- Disabled in conf.lua to avoid window flicker on early exit
  require('love.window')

  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    fullscreen = parsedArgs.fullscreen,
    highdpi = parsedArgs.high_dpi,

    minwidth = 800,
    minheight = 600,

    msaa = parsedArgs.msaa,
    resizable = true,
  })

  love.graphics.setBackgroundColor(0.125, 0.125, 0.125, 1)

  if mesher == "surface-splatting" then
    shader = love.graphics.newShader([[
      varying vec3 VaryingPosition;
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
      uniform mat4 ModelMatrix;
      attribute vec3 VertexNormal;
      attribute vec3 DiskCenter;
      varying vec3 VaryingPosition;
      varying vec3 VaryingNormal;

      vec4 position(mat4 transform_projection, vec4 vertex_position)
      {
        VaryingPosition = vec3(ModelMatrix * vertex_position);
        VaryingNormal = mat3(ModelMatrix) * VertexNormal;
        vec4 result = transform_projection * ModelMatrix * vertex_position;
        // result.z = (transform_projection * vec4(DiskCenter, 1)).z;
        return result;
      }
    ]])
  else
    shader = love.graphics.newShader([[
      varying vec3 VaryingPosition;
      varying vec3 VaryingNormal;

      vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
      {
        vec3 normal = normalize(VaryingNormal);
        vec3 sunLighting = dot(normalize(vec3(-2, -8, 4)), normal) * 3 * vec3(1, 0.5, 0.25);
        vec3 skyLighting = 1 * vec3(0.25, 0.5, 1);
        vec3 lighting = sunLighting + skyLighting;
        return vec4(lighting, 1) * color;
      }
    ]], [[
      uniform mat4 ModelMatrix;
      attribute vec3 VertexNormal;
      varying vec3 VaryingPosition;
      varying vec3 VaryingNormal;

      vec4 position(mat4 transform_projection, vec4 vertex_position)
      {
        VaryingPosition = vec3(ModelMatrix * vertex_position);
        VaryingNormal = mat3(ModelMatrix) * VertexNormal;
        return transform_projection * ModelMatrix * vertex_position;
      }
    ]])
  end

  local boxTransform = love.math.newTransform()
  boxTransform:apply(setTranslation3(love.math.newTransform(), 0, -0.375, 0.875))
  boxTransform:apply(setRotation3(love.math.newTransform(), 1, 0, 0, 0.125 * pi))
  boxTransform:apply(setRotation3(love.math.newTransform(), 0, 0, 1, 0.125 * pi))

  sculpture = {
    edits = {
      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(-0.5, -0.25):inverse(),
        radius = 0.5,
        blendRange = 0,
        color = {0.5, 1, 0.25, 1},
        noise = {},
      },

      {
        operation = "union",
        primitive = "sphere",
        inverseTransform = love.math.newTransform(0.5, 0.25):inverse(),
        radius = 0.75,
        blendRange = 0.5,
        color = {0.25, 0.75, 1, 1},

        noise = {
          amplitude = 0.5,
          frequency = 2.5,
          octaves = 2.5,
        },
      },

      {
        operation = "subtraction",
        primitive = "sphere",
        inverseTransform = translate3(love.math.newTransform(), 0, -0.25, 0.5):inverse(),
        radius = 0.5,
        blendRange = 0.25,
        color = {1, 0.5, 0.25, 1},
        noise = {},
      },

      {
        operation = "union",
        primitive = "box",
        inverseTransform = boxTransform:inverse(),
        size = {0.25, 0.125, 0.5},
        radius = 0,
        blendRange = 0,
        color = {1, 0.75, 0.25, 1},
        noise = {},
      },
    }
  }

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

  -- if mesher == "dual-contouring" then
  --   local grid = dualContouring.newGrid(
  --     sizeX, sizeY, sizeZ, minX, minY, minZ, maxX, maxY, maxZ)

  --   mesh = dualContouring.newMeshFromEdits(sculpture.edits, grid)
  -- elseif mesher == "dual-contouring-2" then
  --   local grid = dualContouring2.newGrid(
  --     sizeX, sizeY, sizeZ, minX, minY, minZ, maxX, maxY, maxZ)

  --   mesh = dualContouring2.newMeshFromEdits(sculpture.edits, grid)
  -- else
  --   -- mesh, disks = surfaceSplatting.newMeshFromEdits(
  --   --   sculpture.edits, minX, minY, minZ, maxX, maxY, maxZ, sizeX, sizeY, sizeZ)
  -- end

  angle = 0

  love.thread.newThread("gutter/worker.lua"):start()
  workerInputChannel = love.thread.getChannel("workerInput")

  local size = 16

  while size <= 128 do
    workerInputChannel:push({
      mesher = mesher,
      edits = sculpture.edits,

      minX = minX,
      minY = minY,
      minZ = minZ,

      maxX = maxX,
      maxY = maxY,
      maxZ = maxZ,

      sizeX = size,
      sizeY = size,
      sizeZ = size,
    })

    size = 2 * size
  end

  workerOutputChannel = love.thread.getChannel("workerOutput")
end

function love.update(dt)
  local output = workerOutputChannel:pop()

  if output and #output.vertices >= 3 then
    if mesh then
      mesh:release()
      mesh = nil
    end

    if mesher == "surface-splatting" then
      local vertexFormat = {
        {"VertexPosition", "float", 3},
        {"VertexNormal", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "byte", 4},
        {"DiskCenter", "float", 3},
      }

      mesh = love.graphics.newMesh(vertexFormat, output.vertices, "triangles")
      mesh:setVertexMap(output.vertexMap)
    else
      local vertexFormat = {
        {"VertexPosition", "float", 3},
        {"VertexNormal", "float", 3},
        {"VertexColor", "byte", 4},
      }

      mesh = love.graphics.newMesh(vertexFormat, output.vertices, "triangles")
    end
  end
end

function love.draw()
  love.graphics.push()
  local width, height = love.graphics.getDimensions()

  if editor then
    love.graphics.setScissor(200, 0, width - 400, height)
  end

  love.graphics.translate(0.5 * width, 0.5 * height)

  local scale = 0.375 * height
  love.graphics.scale(scale)
  love.graphics.setLineWidth(1 / scale)

  local transform = love.math.newTransform()
  setRotation3(transform, 0, 1, 0, angle)

  if mesher == "surface-splatting" then
    if mesh then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setShader(shader)
      shader:send("ModelMatrix", transform)
      love.graphics.setMeshCullMode("back")
      love.graphics.setDepthMode("less", true)
      love.graphics.draw(mesh)
      love.graphics.setDepthMode()
      love.graphics.setMeshCullMode("none")
      love.graphics.setShader(nil)
    end
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader(shader)
    shader:send("ModelMatrix", transform)
    love.graphics.setMeshCullMode("back")
    love.graphics.setDepthMode("less", true)
    love.graphics.draw(mesh)
    love.graphics.setDepthMode()
    love.graphics.setMeshCullMode("none")
    love.graphics.setShader(nil)
  end

  if editor then
    love.graphics.setColor(1, 0.25, 0, 0.5)
    love.graphics.line(-0.5 * width / scale, 0, 0.5 * width / scale, 0)

    love.graphics.setColor(1, 0.25, 0, 1)
    love.graphics.setDepthMode("lequal", false)
    love.graphics.line(-0.5 * width / scale, 0, 0.5 * width / scale, 0)
    love.graphics.setDepthMode()

    love.graphics.setColor(0.25, 1, 0, 0.5)
    love.graphics.line(0, -0.5 * height / scale, 0, 0.5 * height / scale)

    love.graphics.setColor(0.25, 1, 0, 1)
    love.graphics.setDepthMode("lequal", false)
    love.graphics.line(0, -0.5 * height / scale, 0, 0.5 * height / scale)
    love.graphics.setDepthMode()

    for i, edit in ipairs(sculpture.edits) do
      local x, y, z = transformPoint3(transform, transformPoint3(edit.inverseTransform:inverse(), 0, 0, 0))

      if edit.operation == "union" then
        love.graphics.setColor(0.25, 1, 0, 0.5)
      else
        love.graphics.setColor(1, 0.25, 0, 0.5)
      end

      love.graphics.circle("line", x, y, edit.scale, 64)

      if edit.operation == "union" then
        love.graphics.setColor(0.25, 1, 0, 1)
      else
        love.graphics.setColor(1, 0.25, 0, 1)
      end

      love.graphics.setDepthMode("lequal", false)
      love.graphics.circle("line", x, y, edit.scale, 64)
      love.graphics.setDepthMode()
    end
  end

  love.graphics.pop()

  if editor then
    love.graphics.setScissor()
  end

  if editor then
    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", 0, 0, 200, height)

    local font = love.graphics.getFont()
    local fontWidth = font:getWidth("M")
    local fontHeight = font:getHeight()

    for i, edit in ipairs(sculpture.edits) do
      love.graphics.setColor(1, 1, 1, 1)
      -- love.graphics.rectangle("line", 0, 2 * (i - 1) * fontHeight, 200, 2 * fontHeight)
      love.graphics.print(edit.operation .. " " .. edit.primitive, fontWidth, floor((2 * (i - 1) + 0.5) * fontHeight))

      love.graphics.setColor(edit.color)
      love.graphics.circle("fill", 200 - fontHeight, (2 * (i - 1) + 1) * fontHeight, floor(0.5 * fontHeight))
    end

    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", width - 200, 0, 200, height)
  end
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

function love.mousemoved(x, y, dx, dy, istouch)
  if editor and love.mouse.isDown(1) then
    local sensitivity = 1 / 128
    local transform = sculpture.edits[3].inverseTransform:inverse()
    transform = setTranslation3(love.math.newTransform(), sensitivity * dx, sensitivity * dy, 0) * transform
    sculpture.edits[3].inverseTransform = transform:inverse()

    workerInputChannel:clear()

    local minX = -2
    local minY = -2
    local minZ = -2

    local maxX = 2
    local maxY = 2
    local maxZ = 2

    local size = 16

    while size <= 128 do
      workerInputChannel:push({
        mesher = mesher,
        edits = sculpture.edits,

        minX = minX,
        minY = minY,
        minZ = minZ,

        maxX = maxX,
        maxY = maxY,
        maxZ = maxZ,

        sizeX = size,
        sizeY = size,
        sizeZ = size,
      })

      size = 2 * size
    end
  end
end

function love.threaderror(thread, errorstr)
  print("Thread error: " .. errorstr)
end

function love.wheelmoved(x, y)
  angle = angle - x / 16 * pi
end
