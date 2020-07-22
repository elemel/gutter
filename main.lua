local argparse = require("argparse")
local gutterMath = require("gutter.math")
local quaternion = require("gutter.quaternion")
local Slab = require("Slab")

local floor = math.floor
local fromEulerAngles = quaternion.fromEulerAngles
local pi = math.pi
local setRotation3 = gutterMath.setRotation3
local setTranslation3 = gutterMath.setTranslation3
local transformPoint3 = gutterMath.transformPoint3
local translate3 = gutterMath.translate3
local upper = string.upper

local selection

local function capitalize(s)
  s = s:gsub("^%l", upper)
  return s
end

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

  if mesher ~= "dual-contouring" and mesher ~= "surface-splatting" then
    print("Error: argument for option '--mesher' must be one of 'dual-contouring', 'surface-splatting'")
    love.event.quit(1)
    return
  end

  -- Disabled in conf.lua to avoid window flicker on early exit
  require('love.window')

  love.window.setTitle("Gutter")

  love.window.setMode(800, 600, {
    fullscreen = parsedArgs.fullscreen,
    -- highdpi = parsedArgs.high_dpi,

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

  sculpture = {
    edits = {
      {
        operation = "union",
        blendRange = 0,

        position = {-0.5, -0.25, 0},
        rotation = {0, 0, 0, 1},

        color = {0.5, 1, 0.25, 1},
        roundedBox = {1, 1, 1, 0.5},

        noise = {
          amplitude = 1,
          frequency = 1,
          gain = 0.5,
          lacunarity = 2,
          octaves = 0,
        },
      },

      {
        operation = "union",
        blendRange = 0.5,

        position = {0.5, 0.25, 0},
        rotation = {0, 0, 0, 1},

        color = {0.25, 0.75, 1, 1},
        roundedBox = {1.5, 1.5, 1.5, 0.75},

        noise = {
          amplitude = 0.5,
          frequency = 2.5,
          gain = 0.5,
          lacunarity = 2,
          octaves = 2.5,
        },
      },

      {
        operation = "subtraction",
        blendRange = 0.25,

        position = {0, -0.25, 0.5},
        rotation = {0, 0, 0, 1},

        color = {1, 0.5, 0.25, 1},
        roundedBox = {1, 1, 1, 0.5},

        noise = {
          amplitude = 1,
          frequency = 1,
          gain = 0.5,
          lacunarity = 2,
          octaves = 0,
        },
      },

      {
        operation = "union",
        blendRange = 0,

        position = {0, -0.375, 0.75},
        rotation = {fromEulerAngles("xzy", 0.125 * math.pi, 0.375 * math.pi, -0.0625 * math.pi)},

        color = {1, 0.75, 0.25, 1},
        roundedBox = {0.25, 0.125, 0.5, 0},

        noise = {
          amplitude = 1,
          frequency = 1,
          gain = 0.5,
          lacunarity = 2,
          octaves = 0,
        },
      },
    }
  }

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

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

  Slab.SetINIStatePath(nil)
  Slab.Initialize(arg)
end

local combo = {value = 1, items = {'A', 'B', 'C'}}

local operations = {"subtraction", "union"}
local selectableOperations = {"Subtraction", "Union"}

local function index(t, v)
  for i, v2 in ipairs(t) do
    if v2 == v then
      return i
    end
  end

  return nil
end

function love.update(dt)
  Slab.Update(dt)

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

  local width, height = love.graphics.getDimensions()

  do
    Slab.BeginWindow("edits", {
      X = 0,
      Y = 0,

      W = 200 - 4,
      H = height - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
      NoOutline = true,
    })

    Slab.Text("Edits")
    Slab.Separator()

    for i, edit in ipairs(sculpture.edits) do
      if Slab.TextSelectable(capitalize(edit.operation) .. " #" .. i, {IsSelected = (selection == i)}) then
        if selection == i then
          selection = nil
        else
          selection = i
        end
      end
    end

    Slab.EndWindow()
  end

  do
    Slab.BeginWindow("properties", {
      X = width - 200,
      Y = 0,

      W = 200 - 4,
      H = height - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
      NoOutline = true,
    })

    Slab.Text("Properties")
    Slab.Separator()

    if selection then
      local edit = sculpture.edits[selection]

      do
        Slab.BeginLayout("operation", {Columns = 2, ExpandW = true})

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Operation")

          Slab.SetLayoutColumn(2)
          local selectedOperation = selectableOperations[index(operations, edit.operation)]

          if Slab.BeginComboBox("operation", {Selected = selectedOperation}) then
            for i, v in ipairs(selectableOperations) do
              if Slab.TextSelectable(v) then
                edit.operation = operations[i]
                remesh()
              end
            end

            Slab.EndComboBox()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blend Range")

          Slab.SetLayoutColumn(2)

          if Slab.Input("blendRange", {Align = "left", Text = tostring(edit.blendRange)}) then
            edit.blendRange = tonumber(Slab.GetInputText()) or edit.blendRange
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Position")
        Slab.BeginLayout("position", {Columns = 2, ExpandW = true})
        local x, y, z = unpack(edit.position)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("X")

          Slab.SetLayoutColumn(2)

          if Slab.Input("x", {Align = "left", Text = tostring(x)}) then
            edit.position[1] = tonumber(Slab.GetInputText()) or x
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Y")

          Slab.SetLayoutColumn(2)

          if Slab.Input("y", {Align = "left", Text = tostring(y)}) then
            edit.position[2] = tonumber(Slab.GetInputText()) or y
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Z")

          Slab.SetLayoutColumn(2)

          if Slab.Input("z", {Align = "left", Text = tostring(z)}) then
            edit.position[3] = tonumber(Slab.GetInputText()) or z
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Rotation")
        Slab.BeginLayout("rotation", {Columns = 2, ExpandW = true})
        local x, y, z, w = unpack(edit.rotation)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QX")

          Slab.SetLayoutColumn(2)

          if Slab.Input("rotationX", {Align = "left", Text = tostring(x)}) then
            edit.rotation[1] = tonumber(Slab.GetInputText()) or edit.rotation[1]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QY")

          Slab.SetLayoutColumn(2)

          if Slab.Input("rotationY", {Align = "left", Text = tostring(y)}) then
            edit.rotation[2] = tonumber(Slab.GetInputText()) or edit.rotation[2]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QZ")

          Slab.SetLayoutColumn(2)

          if Slab.Input("rotationZ", {Align = "left", Text = tostring(z)}) then
            edit.rotation[3] = tonumber(Slab.GetInputText()) or edit.rotation[3]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QW")

          Slab.SetLayoutColumn(2)

          if Slab.Input("rotationW", {Align = "left", Text = tostring(w)}) then
            edit.rotation[4] = tonumber(Slab.GetInputText()) or edit.rotation[4]
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Color")
        Slab.BeginLayout("color", {Columns = 2, ExpandW = true})
        local red, green, blue, alpha = unpack(edit.color)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Red")

          Slab.SetLayoutColumn(2)

          if Slab.Input("red", {Align = "left", Text = tostring(red)}) then
            edit.color[1] = tonumber(Slab.GetInputText()) or edit.color[1]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Green")

          Slab.SetLayoutColumn(2)

          if Slab.Input("green", {Align = "left", Text = tostring(green)}) then
            edit.color[2] = tonumber(Slab.GetInputText()) or edit.color[2]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blue")

          Slab.SetLayoutColumn(2)

          if Slab.Input("blue", {Align = "left", Text = tostring(blue)}) then
            edit.color[3] = tonumber(Slab.GetInputText()) or edit.color[3]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Alpha")

          Slab.SetLayoutColumn(2)

          if Slab.Input("alpha", {Align = "left", Text = tostring(alpha)}) then
            edit.color[4] = tonumber(Slab.GetInputText()) or edit.color[4]
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Rounded Box")
        Slab.BeginLayout("roundedBox", {Columns = 2, ExpandW = true})
        local width, height, depth, radius = unpack(edit.roundedBox)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Width")

          Slab.SetLayoutColumn(2)

          if Slab.Input("width", {Align = "left", Text = tostring(width)}) then
            edit.roundedBox[1] = tonumber(Slab.GetInputText()) or edit.roundedBox[1]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Height")

          Slab.SetLayoutColumn(2)

          if Slab.Input("height", {Align = "left", Text = tostring(height)}) then
            edit.roundedBox[2] = tonumber(Slab.GetInputText()) or edit.roundedBox[2]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Depth")

          Slab.SetLayoutColumn(2)

          if Slab.Input("depth", {Align = "left", Text = tostring(depth)}) then
            edit.roundedBox[3] = tonumber(Slab.GetInputText()) or edit.roundedBox[3]
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Radius")

          Slab.SetLayoutColumn(2)

          if Slab.Input("radius", {Align = "left", Text = tostring(radius)}) then
            edit.roundedBox[4] = tonumber(Slab.GetInputText()) or edit.roundedBox[4]
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Noise")
        Slab.BeginLayout("noise", {Columns = 2, ExpandW = true})
        local noise = edit.noise

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Octaves")

          Slab.SetLayoutColumn(2)

          if Slab.Input("octaves", {Align = "left", Text = tostring(noise.octaves)}) then
            noise.octaves = tonumber(Slab.GetInputText()) or noise.octaves
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Frequency")

          Slab.SetLayoutColumn(2)

          if Slab.Input("frequency", {Align = "left", Text = tostring(noise.frequency)}) then
            noise.frequency = tonumber(Slab.GetInputText()) or noise.frequency
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Amplitude")

          Slab.SetLayoutColumn(2)

          if Slab.Input("amplitude", {Align = "left", Text = tostring(noise.amplitude)}) then
            noise.amplitude = tonumber(Slab.GetInputText()) or noise.amplitude
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Lacunarity")

          Slab.SetLayoutColumn(2)

          if Slab.Input("lacunarity", {Align = "left", Text = tostring(noise.lacunarity)}) then
            noise.lacunarity = tonumber(Slab.GetInputText()) or noise.lacunarity
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Gain")

          Slab.SetLayoutColumn(2)

          if Slab.Input("gain", {Align = "left", Text = tostring(noise.gain)}) then
            noise.gain = tonumber(Slab.GetInputText()) or noise.gain
            remesh()
          end
        end

        Slab.EndLayout()
      end
    end

    Slab.EndWindow()
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
      local x, y, z = transformPoint3(transform, unpack(edit.position))

      if edit.operation == "union" then
        love.graphics.setColor(0.25, 1, 0, 0.5)
      else
        love.graphics.setColor(1, 0.25, 0, 0.5)
      end

      love.graphics.circle("line", x, y, edit.radius, 64)

      if edit.operation == "union" then
        love.graphics.setColor(0.25, 1, 0, 1)
      else
        love.graphics.setColor(1, 0.25, 0, 1)
      end

      love.graphics.setDepthMode("lequal", false)
      love.graphics.circle("line", x, y, edit.radius, 64)
      love.graphics.setDepthMode()
    end
  end

  love.graphics.pop()

  if editor then
    love.graphics.setScissor()
  end

  Slab.Draw()
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

    sculpture.edits[3].position[1] = sculpture.edits[3].position[1] + sensitivity * dx
    sculpture.edits[3].position[2] = sculpture.edits[3].position[2] + sensitivity * dy

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

function remesh()
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
