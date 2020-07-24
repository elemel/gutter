local argparse = require("argparse")
local gutterMath = require("gutter.math")
local quaternion = require("gutter.quaternion")
local Slab = require("Slab")

local clamp = gutterMath.clamp
local floor = math.floor
local fromEulerAngles = quaternion.fromEulerAngles
local max = math.max
local min = math.min
local pi = math.pi
local round3 = gutterMath.round3
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
        vec3 sunLighting = max(0, dot(normalize(vec3(-2, -8, 4)), normal)) * 3 * vec3(1, 0.5, 0.25);
        vec3 skyLighting = vec3(0.25, 0.5, 1) * (0.5 - 0.5 * normal.y);
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
        vec4 result = transform_projection * ModelMatrix * vertex_position;
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

  instructions = {
    {
      operation = "union",
      blending = 0,

      position = {-0.5, -0.25, 0},
      orientation = {0, 0, 0, 1},

      color = {0.5, 1, 0.25, 1},
      shape = {1, 1, 1, 1},

      noise = {
        octaves = 0,
        amplitude = 1,
        frequency = 1,
        gain = 0.5,
        lacunarity = 1,
      },
    },

    {
      operation = "union",
      blending = 0.5,

      position = {0.5, 0.25, 0},
      orientation = {0, 0, 0, 1},

      color = {0.25, 0.75, 1, 1},
      shape = {1.5, 1.5, 1.5, 1},

      noise = {
        octaves = 3,
        amplitude = 0.5,
        frequency = 1,
        gain = 0.5,
        lacunarity = 1,
      },
    },

    {
      operation = "subtraction",
      blending = 0.25,

      position = {0, -0.25, 0.5},
      orientation = {0, 0, 0, 1},

      color = {1, 0.5, 0.25, 1},
      shape = {1, 1, 1, 1},

      noise = {
        octaves = 0,
        amplitude = 1,
        frequency = 1,
        gain = 0.5,
        lacunarity = 1,
      },
    },

    {
      operation = "union",
      blending = 0,

      position = {0, -0.375, 0.75},
      orientation = {fromEulerAngles("xzy", 0.125 * pi, 0.375 * pi, -0.0625 * pi)},

      color = {1, 0.75, 0.25, 1},
      shape = {0.5, 0.25, 1, 0},

      noise = {
        octaves = 0,
        amplitude = 1,
        frequency = 1,
        gain = 0.5,
        lacunarity = 1,
      },
    },
  }

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

  angle = 0

  workerInputVersion = 1
  workerOutputVersion = 1

  workerInputChannel = love.thread.getChannel("workerInput")
  workerOutputChannel = love.thread.getChannel("workerOutput")

  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()

  remesh()

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

  if output and output.version > workerOutputVersion and #output.vertices >= 3 then
    workerOutputVersion = output.version

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
    Slab.BeginWindow("instructions", {
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

    Slab.Text("Instructions", {Color = {1, 1, 1}})
    Slab.Separator()

    do
      Slab.BeginLayout("newAndDelete", {Columns = 2})
      Slab.SetLayoutColumn(1)

      if Slab.Button("New", {W = 94}) then
        table.insert(instructions, {
          operation = "union",
          blending = 0,

          position = {0, 0, 0},
          orientation = {0, 0, 0, 1},

          color = {0.5, 0.5, 0.5, 1},
          shape = {1, 1, 1, 1},

          noise = {
            octaves = 0,
            amplitude = 1,
            frequency = 1,
            gain = 0.5,
            lacunarity = 1,
          },
        })

        selection = #instructions
        remesh()
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Delete", {W = 94, Disabled = selection == nil}) then
        table.remove(instructions, selection)

        if #instructions == 0 then
          selection = nil
        else
          selection = min(selection, #instructions)
        end

        remesh()
      end

      Slab.EndLayout()
    end

    Slab.Separator()

    for i = #instructions, 1, -1 do
      instruction = instructions[i]

      if Slab.TextSelectable(capitalize(instruction.operation) .. " #" .. i, {IsSelected = (selection == i)}) then
        if selection == i then
          selection = nil
        else
          selection = i
        end
      end
    end

    Slab.Separator()

    do
      Slab.BeginLayout("order", {Columns = 2})
      Slab.SetLayoutColumn(1)

      if Slab.Button("Up", {Disabled = selection == nil or selection == #instructions, W = 94}) then
        instructions[selection], instructions[selection + 1] = instructions[selection + 1], instructions[selection]
        selection = selection + 1
        remesh()
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Top", {Disabled = selection == nil or selection == #instructions, W = 94}) then
        local instruction = instructions[selection]
        table.remove(instructions, selection)
        table.insert(instructions, instruction)
        selection = #instructions
        remesh()
      end

      Slab.SetLayoutColumn(1)

      if Slab.Button("Down", {Disabled = selection == nil or selection == 1, W = 94}) then
        instructions[selection], instructions[selection - 1] = instructions[selection - 1], instructions[selection]
        selection = selection - 1
        remesh()
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Bottom", {Disabled = selection == nil or selection == 1, W = 94}) then
        local instruction = instructions[selection]
        table.remove(instructions, selection)
        table.insert(instructions, 1, instruction)
        selection = 1
        remesh()
      end

      Slab.EndLayout()
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

    Slab.Text("Properties", {Color = {1, 1, 1}})
    Slab.Separator()

    if selection then
      local instruction = instructions[selection]

      do
        Slab.BeginLayout("operation", {Columns = 2, ExpandW = true})

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Operation")

          Slab.SetLayoutColumn(2)
          local selectedOperation = selectableOperations[index(operations, instruction.operation)]

          if Slab.BeginComboBox("operation", {Selected = selectedOperation}) then
            for i, v in ipairs(selectableOperations) do
              if Slab.TextSelectable(v) then
                instruction.operation = operations[i]
                remesh()
              end
            end

            Slab.EndComboBox()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blending")

          Slab.SetLayoutColumn(2)

          if Slab.Input("blending", {Align = "left", Text = tostring(instruction.blending)}) then
            instruction.blending = clamp(tonumber(Slab.GetInputText()) or instruction.blending, 0, 1)
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Position")
        Slab.BeginLayout("position", {Columns = 2, ExpandW = true})
        local x, y, z = unpack(instruction.position)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("X")

          Slab.SetLayoutColumn(2)

          if Slab.Input("x", {Align = "left", Text = tostring(x)}) then
            instruction.position[1] = tonumber(Slab.GetInputText()) or x
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Y")

          Slab.SetLayoutColumn(2)

          if Slab.Input("y", {Align = "left", Text = tostring(y)}) then
            instruction.position[2] = tonumber(Slab.GetInputText()) or y
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Z")

          Slab.SetLayoutColumn(2)

          if Slab.Input("z", {Align = "left", Text = tostring(z)}) then
            instruction.position[3] = tonumber(Slab.GetInputText()) or z
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Orientation")
        Slab.BeginLayout("orientation", {Columns = 2, ExpandW = true})
        local orientation = instruction.orientation
        local qx, qy, qz, qw = unpack(orientation)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QX")

          Slab.SetLayoutColumn(2)

          if Slab.Input("qx", {Align = "left", Text = tostring(qx)}) then
            orientation[1] = tonumber(Slab.GetInputText()) or qx

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QY")

          Slab.SetLayoutColumn(2)

          if Slab.Input("qy", {Align = "left", Text = tostring(qy)}) then
            orientation[2] = tonumber(Slab.GetInputText()) or qy

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QZ")

          Slab.SetLayoutColumn(2)

          if Slab.Input("qz", {Align = "left", Text = tostring(qz)}) then
            orientation[3] = tonumber(Slab.GetInputText()) or qz

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QW")

          Slab.SetLayoutColumn(2)

          if Slab.Input("qw", {Align = "left", Text = tostring(qw)}) then
            orientation[4] = tonumber(Slab.GetInputText()) or qw

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Color")
        Slab.BeginLayout("color", {Columns = 2, ExpandW = true})
        local red, green, blue, alpha = unpack(instruction.color)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Red")

          Slab.SetLayoutColumn(2)

          if Slab.Input("red", {Align = "left", Text = tostring(red)}) then
            instruction.color[1] = clamp(tonumber(Slab.GetInputText()) or red, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Green")

          Slab.SetLayoutColumn(2)

          if Slab.Input("green", {Align = "left", Text = tostring(green)}) then
            instruction.color[2] = clamp(tonumber(Slab.GetInputText()) or green, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blue")

          Slab.SetLayoutColumn(2)

          if Slab.Input("blue", {Align = "left", Text = tostring(blue)}) then
            instruction.color[3] = clamp(tonumber(Slab.GetInputText()) or blue, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Alpha")

          Slab.SetLayoutColumn(2)

          if Slab.Input("alpha", {Align = "left", Text = tostring(alpha)}) then
            instruction.color[4] = clamp(tonumber(Slab.GetInputText()) or alpha, 0, 1)
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Shape")
        Slab.BeginLayout("shape", {Columns = 2, ExpandW = true})
        local width, height, depth, rounding = unpack(instruction.shape)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Width")

          Slab.SetLayoutColumn(2)

          if Slab.Input("width", {Align = "left", Text = tostring(width)}) then
            instruction.shape[1] = max(0, tonumber(Slab.GetInputText()) or width)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Height")

          Slab.SetLayoutColumn(2)

          if Slab.Input("height", {Align = "left", Text = tostring(height)}) then
            instruction.shape[2] = max(0, tonumber(Slab.GetInputText()) or height)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Depth")

          Slab.SetLayoutColumn(2)

          if Slab.Input("depth", {Align = "left", Text = tostring(depth)}) then
            instruction.shape[3] = max(0, tonumber(Slab.GetInputText()) or depth)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Rounding")

          Slab.SetLayoutColumn(2)

          if Slab.Input("rounding", {Align = "left", Text = tostring(rounding)}) then
            instruction.shape[4] = clamp(tonumber(Slab.GetInputText()) or rounding, 0, 1)
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Noise")
        Slab.BeginLayout("noise", {Columns = 2, ExpandW = true})
        local noise = instruction.noise

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Octaves")

          Slab.SetLayoutColumn(2)

          if Slab.Input("octaves", {Align = "left", Text = tostring(noise.octaves)}) then
            noise.octaves = max(0, tonumber(Slab.GetInputText()) or noise.octaves)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Amplitude")

          Slab.SetLayoutColumn(2)

          if Slab.Input("amplitude", {Align = "left", Text = tostring(noise.amplitude)}) then
            noise.amplitude = clamp(tonumber(Slab.GetInputText()) or noise.amplitude, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Frequency")

          Slab.SetLayoutColumn(2)

          if Slab.Input("frequency", {Align = "left", Text = tostring(noise.frequency)}) then
            noise.frequency = clamp(tonumber(Slab.GetInputText()) or noise.frequency, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Gain")

          Slab.SetLayoutColumn(2)

          if Slab.Input("gain", {Align = "left", Text = tostring(noise.gain)}) then
            noise.gain = clamp(tonumber(Slab.GetInputText()) or noise.gain, 0, 1)
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Lacunarity")

          Slab.SetLayoutColumn(2)

          if Slab.Input("lacunarity", {Align = "left", Text = tostring(noise.lacunarity)}) then
            noise.lacunarity = clamp(tonumber(Slab.GetInputText()) or noise.lacunarity, 0, 1)
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
    -- love.graphics.setColor(1, 0.25, 0, 0.5)
    -- love.graphics.line(-0.5 * width / scale, 0, 0.5 * width / scale, 0)

    -- love.graphics.setColor(1, 0.25, 0, 1)
    -- love.graphics.setDepthMode("lequal", false)
    -- love.graphics.line(-0.5 * width / scale, 0, 0.5 * width / scale, 0)
    -- love.graphics.setDepthMode()

    -- love.graphics.setColor(0.25, 1, 0, 0.5)
    -- love.graphics.line(0, -0.5 * height / scale, 0, 0.5 * height / scale)

    -- love.graphics.setColor(0.25, 1, 0, 1)
    -- love.graphics.setDepthMode("lequal", false)
    -- love.graphics.line(0, -0.5 * height / scale, 0, 0.5 * height / scale)
    -- love.graphics.setDepthMode()

    for i, instruction in ipairs(instructions) do
      if i == selection then
        local instructionTransform =
          transform *
          setTranslation3(love.math.newTransform(), unpack(instruction.position)) *
          quaternion.toTransform(unpack(instruction.orientation))

        local width, height, depth, rounding = unpack(instruction.shape)

        local x1, y1, z1 = transformPoint3(instructionTransform, -0.5 * width, -0.5 * height, -0.5 * depth)
        local x2, y2, z2 = transformPoint3(instructionTransform, 0.5 * width, -0.5 * height, -0.5 * depth)
        local x3, y3, z3 = transformPoint3(instructionTransform, -0.5 * width, 0.5 * height, -0.5 * depth)
        local x4, y4, z4 = transformPoint3(instructionTransform, 0.5 * width, 0.5 * height, -0.5 * depth)
        local x5, y5, z5 = transformPoint3(instructionTransform, -0.5 * width, -0.5 * height, 0.5 * depth)
        local x6, y6, z6 = transformPoint3(instructionTransform, 0.5 * width, -0.5 * height, 0.5 * depth)
        local x7, y7, z7 = transformPoint3(instructionTransform, -0.5 * width, 0.5 * height, 0.5 * depth)
        local x8, y8, z8 = transformPoint3(instructionTransform, 0.5 * width, 0.5 * height, 0.5 * depth)

        local lineWidth = love.graphics.getLineWidth()

        love.graphics.setLineWidth(3 * lineWidth)
        love.graphics.setColor(0, 0, 0, 1)

        love.graphics.line(x1, y1, x2, y2)
        love.graphics.line(x1, y1, x3, y3)
        love.graphics.line(x1, y1, x5, y5)
        love.graphics.line(x2, y2, x4, y4)
        love.graphics.line(x2, y2, x6, y6)
        love.graphics.line(x3, y3, x4, y4)
        love.graphics.line(x3, y3, x7, y7)
        love.graphics.line(x4, y4, x8, y8)
        love.graphics.line(x5, y5, x6, y6)
        love.graphics.line(x5, y5, x7, y7)
        love.graphics.line(x6, y6, x8, y8)
        love.graphics.line(x7, y7, x8, y8)

        love.graphics.setLineWidth(lineWidth)
        love.graphics.setColor(1, 1, 1, 1)

        love.graphics.line(x1, y1, x2, y2)
        love.graphics.line(x1, y1, x3, y3)
        love.graphics.line(x1, y1, x5, y5)
        love.graphics.line(x2, y2, x4, y4)
        love.graphics.line(x2, y2, x6, y6)
        love.graphics.line(x3, y3, x4, y4)
        love.graphics.line(x3, y3, x7, y7)
        love.graphics.line(x4, y4, x8, y8)
        love.graphics.line(x5, y5, x6, y6)
        love.graphics.line(x5, y5, x7, y7)
        love.graphics.line(x6, y6, x8, y8)
        love.graphics.line(x7, y7, x8, y8)

        -- if instruction.operation == "union" then
        --   love.graphics.setColor(0.25, 1, 0, 0.5)
        -- else
        --   love.graphics.setColor(1, 0.25, 0, 0.5)
        -- end

        -- love.graphics.circle("line", x, y, instruction.radius, 64)

        -- if instruction.operation == "union" then
        --   love.graphics.setColor(0.25, 1, 0, 1)
        -- else
        --   love.graphics.setColor(1, 0.25, 0, 1)
        -- end

        -- love.graphics.setDepthMode("lequal", false)
        -- love.graphics.circle("line", x, y, instruction.radius, 64)
        -- love.graphics.setDepthMode()
      end
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

    instructions[3].position[1] = instructions[3].position[1] + sensitivity * dx
    instructions[3].position[2] = instructions[3].position[2] + sensitivity * dy

    remesh()
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

  while size <= 64 do
    workerInputVersion = workerInputVersion + 1

    workerInputChannel:push({
      version = workerInputVersion,
      mesher = mesher,
      instructions = instructions,

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
