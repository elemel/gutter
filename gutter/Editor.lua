local gutterMath = require("gutter.math")
local quaternion = require("gutter.quaternion")
local Slab = require("Slab")

local clamp = gutterMath.clamp
local floor = math.floor
local format = string.format
local fromEulerAngles = quaternion.fromEulerAngles
local max = math.max
local min = math.min
local normalize2 = gutterMath.normalize2
local pi = math.pi
local round3 = gutterMath.round3
local setRotation3 = gutterMath.setRotation3
local setTranslation3 = gutterMath.setTranslation3
local transformPoint3 = gutterMath.transformPoint3
local translate3 = gutterMath.translate3
local upper = string.upper

local function capitalize(s)
  s = s:gsub("^%l", upper)
  return s
end

local Editor = {}
Editor.__index = Editor

function Editor.new(instance, ...)
  instance = instance or {}
  local instance = setmetatable(instance, Editor)
  instance:init(...)
  return instance
end

function Editor:init(parsedArgs)
  mesher = parsedArgs.mesher

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

  viewportTransform = love.math.newTransform()
  cameraTransform = love.math.newTransform()
  worldToScreenTransform = love.math.newTransform()
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

function Editor:update(dt)
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

          if Slab.InputNumberSlider("blending", instruction.blending, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            instruction.blending = Slab.GetInputNumber()
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Position")
        Slab.BeginLayout("position", {Columns = 2, ExpandW = true})
        local position = instruction.position
        local x, y, z = unpack(position)
        local step = 1 / 32

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("X")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("x", x, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[1] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Y")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("y", y, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[2] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Z")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("z", z, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[3] = Slab.GetInputNumber()
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

          if Slab.InputNumberSlider("qx", qx, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[1] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QY")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qy", qy, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[2] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QZ")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qz", qz, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[3] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QW")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qw", qw, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[4] = Slab.GetInputNumber()

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
        local color = instruction.color
        local red, green, blue, alpha = unpack(color)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Red")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("red", red, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[1] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Green")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("green", green, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[2] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blue")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("blue", blue, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[3] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Alpha")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("alpha", alpha, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[4] = Slab.GetInputNumber()
            remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("Shape")
        Slab.BeginLayout("shape", {Columns = 2, ExpandW = true})
        local shape = instruction.shape
        local width, height, depth, rounding = unpack(shape)
        local step = 1 / 32

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Width")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("width", width, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[1] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Height")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("height", height, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[2] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Depth")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("depth", depth, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[3] = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Rounding")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("rounding", rounding, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            shape[4] = Slab.GetInputNumber()
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
        local step = 1 / 32

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Octaves")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("octaves", noise.octaves, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            noise.octaves = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Amplitude")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("amplitude", noise.amplitude, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            noise.amplitude = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Frequency")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("frequency", noise.frequency, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            noise.frequency = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Gain")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("gain", noise.gain, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            noise.gain = Slab.GetInputNumber()
            remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Lacunarity")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("lacunarity", noise.lacunarity, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            noise.lacunarity = Slab.GetInputNumber()
            remesh()
          end
        end

        Slab.EndLayout()
      end
    end

    Slab.EndWindow()
  end
end

function extendLine(x1, y1, x2, y2, r)
  local tangentX, tangentY = normalize2(x2 - x1, y2 - y1)
  return x1 - r * tangentX, y1 - r * tangentY, x2 + r * tangentX, y2 + r * tangentY
end

function Editor:draw()
  local width, height = love.graphics.getDimensions()
  local scale = 0.25

  viewportTransform:reset():translate(0.5 * width, 0.5 * height):scale(height)

  setRotation3(cameraTransform:reset(), 0, 1, 0, angle):apply(love.math.newTransform():setMatrix(
    scale, 0, 0, 0,
    0, scale, 0, 0,
    0, 0, scale, 0,
    0, 0, 0, 1))

  worldToScreenTransform:reset():apply(viewportTransform):apply(cameraTransform)
  love.graphics.setScissor(200, 0, width - 400, height)

  love.graphics.push()
  love.graphics.applyTransform(worldToScreenTransform)

  local transform = love.math.newTransform()

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

  love.graphics.pop()

  for i, instruction in ipairs(instructions) do
    if i == selection then
      local instructionTransform =
        worldToScreenTransform *
        setTranslation3(love.math.newTransform(), unpack(instruction.position)) *
        quaternion.toTransform(unpack(instruction.orientation))

      local width, height, depth, rounding = unpack(instruction.shape)

      local x1, y1, z1 = round3(transformPoint3(instructionTransform, -0.5 * width, -0.5 * height, -0.5 * depth))
      local x2, y2, z2 = round3(transformPoint3(instructionTransform, 0.5 * width, -0.5 * height, -0.5 * depth))
      local x3, y3, z3 = round3(transformPoint3(instructionTransform, -0.5 * width, 0.5 * height, -0.5 * depth))
      local x4, y4, z4 = round3(transformPoint3(instructionTransform, 0.5 * width, 0.5 * height, -0.5 * depth))
      local x5, y5, z5 = round3(transformPoint3(instructionTransform, -0.5 * width, -0.5 * height, 0.5 * depth))
      local x6, y6, z6 = round3(transformPoint3(instructionTransform, 0.5 * width, -0.5 * height, 0.5 * depth))
      local x7, y7, z7 = round3(transformPoint3(instructionTransform, -0.5 * width, 0.5 * height, 0.5 * depth))
      local x8, y8, z8 = round3(transformPoint3(instructionTransform, 0.5 * width, 0.5 * height, 0.5 * depth))

      love.graphics.setLineWidth(4)
      love.graphics.setColor(0, 0, 0, 1)

      love.graphics.line(extendLine(x1, y1, x2, y2, 1))
      love.graphics.line(extendLine(x1, y1, x3, y3, 1))
      love.graphics.line(extendLine(x1, y1, x5, y5, 1))
      love.graphics.line(extendLine(x2, y2, x4, y4, 1))
      love.graphics.line(extendLine(x2, y2, x6, y6, 1))
      love.graphics.line(extendLine(x3, y3, x4, y4, 1))
      love.graphics.line(extendLine(x3, y3, x7, y7, 1))
      love.graphics.line(extendLine(x4, y4, x8, y8, 1))
      love.graphics.line(extendLine(x5, y5, x6, y6, 1))
      love.graphics.line(extendLine(x5, y5, x7, y7, 1))
      love.graphics.line(extendLine(x6, y6, x8, y8, 1))
      love.graphics.line(extendLine(x7, y7, x8, y8, 1))

      love.graphics.setLineWidth(1)
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
    end
  end

  love.graphics.setScissor()
  Slab.Draw()
end

function Editor:mousemoved(x, y, dx, dy, istouch)
  local width, height = love.graphics.getDimensions()

  if 200 < x and x <= width - 200 and selection and love.mouse.isDown(1) then
    local width, height = love.graphics.getDimensions()
    local scale = 0.25

    local viewportTransform = love.math.newTransform():translate(0.5 * width, 0.5 * height):scale(height)
    local cameraTransform = setRotation3(love.math.newTransform(), 0, 1, 0, angle):apply(love.math.newTransform():setMatrix(
      scale, 0, 0, 0,
      0, scale, 0, 0,
      0, 0, scale, 0,
      0, 0, 0, 1))

    local worldToScreenTransform = love.math.newTransform():apply(viewportTransform):apply(cameraTransform)
    local screenToWorldTransform = worldToScreenTransform:inverse()

    local worldX1, worldY1, worldZ1 = transformPoint3(screenToWorldTransform, 0, 0, 0)
    local worldX2, worldY2, worldZ2 = transformPoint3(screenToWorldTransform, dx, dy, 0)

    local worldDx = worldX2 - worldX1
    local worldDy = worldY2 - worldY1
    local worldDz = worldZ2 - worldZ1

    local instruction = instructions[selection]
    local position = instruction.position

    position[1] = position[1] + worldDx
    position[2] = position[2] + worldDy
    position[3] = position[3] + worldDz

    remesh()
  end
end

function Editor:wheelmoved(x, y)
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

return Editor
