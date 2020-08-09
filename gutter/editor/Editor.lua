local DeleteInstructionCommand = require("gutter.editor.commands.DeleteInstructionCommand")
local gutterMath = require("gutter.math")
local gutterTable = require("gutter.table")
local lton = require("lton")
local quaternion = require("gutter.quaternion")
local MoveController = require("gutter.editor.controllers.MoveController")
local NewInstructionCommand = require("gutter.editor.commands.NewInstructionCommand")
local RotateController = require("gutter.editor.controllers.RotateController")
local ScaleController = require("gutter.editor.controllers.ScaleController")
local Slab = require("Slab")

local atan2 = math.atan2
local clamp = gutterMath.clamp
local concat = table.concat
local distance2 = gutterMath.distance2
local dump = lton.dump
local find = gutterTable.find
local floor = math.floor
local format = string.format
local fromEulerAngles = quaternion.fromEulerAngles
local max = math.max
local min = math.min
local normalize2 = gutterMath.normalize2
local normalize3 = gutterMath.normalize3
local pi = math.pi
local round3 = gutterMath.round3
local setRotation3 = gutterMath.setRotation3
local setTranslation3 = gutterMath.setTranslation3
local transformPoint3 = gutterMath.transformPoint3
local transformVector3 = gutterMath.transformVector3
local translate3 = gutterMath.translate3
local upper = string.upper

local Editor = {}
Editor.__index = Editor

function Editor.new(instance, ...)
  instance = instance or {}
  local instance = setmetatable(instance, Editor)
  instance:init(...)
  return instance
end

function Editor:init(config)
  self.modelFilename = config.model
  self.mesher = config.mesher

  if self.mesher == "surface-splatting" then
    self.shader = love.graphics.newShader([[
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
    self.shader = love.graphics.newShader([[
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

  self:log("info", "Using save directory: " .. love.filesystem.getSaveDirectory())

  if config.model then
    local info = love.filesystem.getInfo(config.model)

    if info == nil then
      self:log("error", "No such file: " .. config.model)
    else
      self.model = self:loadModel(config.model)
      self:log("info", "Loaded model: " .. config.model)
    end
  end

  if not self.model then
    self.model = require("resources.models.example")
  end

  self.instructions = self.model.children

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

  self.angle = 0

  self.workerInputVersion = 1
  self.workerOutputVersion = 1

  self.workerInputChannel = love.thread.getChannel("workerInput")
  self.workerOutputChannel = love.thread.getChannel("workerOutput")

  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()
  love.thread.newThread("gutter/worker.lua"):start()

  self:remesh()

  self.camera = {
    position = {0, 0, 0},
    rotation = {0, 0, 0, 1},
  }

  self.viewportTransform = love.math.newTransform()
  self.cameraTransform = love.math.newTransform()
  self.worldToScreenTransform = love.math.newTransform()

  self.colors = {
    blue = {0.25, 0.75, 1, 1},
    green = {0.25, 1, 0.25, 1},
    red = {1, 0.5, 0.25, 1},
    white = {1, 1, 1, 1},
    yellow = {1, 0.75, 0.25, 1},
  }

  self.logColors = {
    debug = self.colors.green,
    error = self.colors.red,
    info = self.colors.white,
    warn = self.colors.yellow,
  }

  self.commandHistory = {}
  self.commandFuture = {}
end

local combo = {value = 1, items = {'A', 'B', 'C'}}

local operations = {"subtraction", "union"}
local selectableOperations = {"Subtraction", "Union"}

function Editor:update(dt)
  Slab.Update(dt)

  local output = self.workerOutputChannel:pop()

  if output and output.version > self.workerOutputVersion and #output.vertices >= 3 then
    self.workerOutputVersion = output.version

    if mesh then
      mesh:release()
      mesh = nil
    end

    if self.mesher == "surface-splatting" then
      local vertexFormat = {
        {"VertexPosition", "float", 3},
        {"VertexNormal", "float", 3},
        {"VertexTexCoord", "float", 2},
        {"VertexColor", "byte", 4},
      }

      mesh = love.graphics.newMesh(vertexFormat, output.vertices, "triangles")
      mesh:setVertexMap(output.vertexMap)
      self:log("debug", "Updated mesh with " .. (#output.vertices / 4) .. " quads")
    else
      local vertexFormat = {
        {"VertexPosition", "float", 3},
        {"VertexNormal", "float", 3},
        {"VertexColor", "byte", 4},
      }

      mesh = love.graphics.newMesh(vertexFormat, output.vertices, "triangles")
      self:log("debug", "Updated mesh with " .. (#output.vertices / 3) .. " triangles")
    end
  end

  local width, height = love.graphics.getDimensions()

  local toolsHeight = 50
  local statusHeight = 50
  local menuHeight = 0

  do
    if Slab.BeginMainMenuBar() then
      if Slab.BeginMenu("File") then
        -- Slab.MenuItem("New")
        -- Slab.MenuItem("Open")
        -- Slab.MenuItem("Save")
        -- Slab.MenuItem("Save As")

        -- Slab.Separator()

        if Slab.MenuItem("Quit") then
            love.event.quit()
        end

        Slab.EndMenu()
      end

      if Slab.BeginMenu("Edit") then
        if #self.commandHistory >= 1 then
          local command = self.commandHistory[#self.commandHistory]

          if Slab.MenuItem("Undo " .. command.title) then
            self:undoCommand()
          end
        end

        if #self.commandFuture >= 1 then
          local command = self.commandFuture[#self.commandFuture]

          if Slab.MenuItem("Redo " .. command.title) then
            self:redoCommand()
          end
        end

        Slab.EndMenu()
      end

      _, menuHeight = Slab.GetWindowSize()
      Slab.EndMainMenuBar()
    end
  end


  do
    Slab.BeginWindow("tools", {
      X = 0,
      Y = menuHeight,

      W = width - 4,
      H = toolsHeight - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
    })

    Slab.EndWindow()
  end

  do
    Slab.BeginWindow("instructions", {
      X = 0,
      Y = menuHeight + toolsHeight,

      W = 200 - 4,
      H = height - menuHeight - toolsHeight - statusHeight - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
    })

    Slab.Text("INSTRUCTIONS")
    Slab.Separator()

    do
      Slab.BeginLayout("newAndDelete", {Columns = 2})
      Slab.SetLayoutColumn(1)

      if Slab.Button("New", {W = 94}) then
        self:doCommand(NewInstructionCommand.new(self))
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Delete", {W = 94, Disabled = self.selection == nil}) then
        self:doCommand(DeleteInstructionCommand.new(self))
      end

      Slab.EndLayout()
    end

    Slab.Separator()

    for i = #self.instructions, 1, -1 do
      local instruction = self.instructions[i]
      local components = instruction.components

      local color = components.operation == "subtraction" and self.colors.red or self.colors.green

      if Slab.TextSelectable(selectableOperations[find(operations, components.operation)] .. " #" .. i, {Color = color, IsSelected = (self.selection == i)}) then
        if self.selection == i then
          self.selection = nil
        else
          self.selection = i
        end
      end
    end

    Slab.Separator()

    do
      Slab.BeginLayout("order", {Columns = 2})
      Slab.SetLayoutColumn(1)

      if Slab.Button("Up", {Disabled = self.selection == nil or self.selection == #self.instructions, W = 94}) then
        self.instructions[self.selection], self.instructions[self.selection + 1] = self.instructions[self.selection + 1], self.instructions[self.selection]
        self.selection = self.selection + 1
        self:remesh()
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Top", {Disabled = self.selection == nil or self.selection == #self.instructions, W = 94}) then
        local instruction = self.instructions[self.selection]
        table.remove(self.instructions, self.selection)
        table.insert(self.instructions, instruction)
        self.selection = #self.instructions
        self:remesh()
      end

      Slab.SetLayoutColumn(1)

      if Slab.Button("Down", {Disabled = self.selection == nil or self.selection == 1, W = 94}) then
        self.instructions[self.selection], self.instructions[self.selection - 1] = self.instructions[self.selection - 1], self.instructions[self.selection]
        self.selection = self.selection - 1
        self:remesh()
      end

      Slab.SetLayoutColumn(2)

      if Slab.Button("Bottom", {Disabled = self.selection == nil or self.selection == 1, W = 94}) then
        local instruction = self.instructions[self.selection]
        table.remove(self.instructions, self.selection)
        table.insert(self.instructions, 1, instruction)
        self.selection = 1
        self:remesh()
      end

      Slab.EndLayout()
    end

    Slab.EndWindow()
  end

  do
    Slab.BeginWindow("properties", {
      X = width - 200,
      Y = menuHeight + toolsHeight,

      W = 200 - 4,
      H = height - menuHeight - toolsHeight - statusHeight - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
    })

    Slab.Text("PROPERTIES")
    Slab.Separator()

    if self.selection then
      local instruction = self.model.children[self.selection]
      local components = instruction.components

      do
        Slab.BeginLayout("operation", {Columns = 2, ExpandW = true})

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Operation")

          Slab.SetLayoutColumn(2)
          local selectedOperation = selectableOperations[find(operations, components.operation)]

          if Slab.BeginComboBox("operation", {Selected = selectedOperation}) then
            for i, v in ipairs(selectableOperations) do
              if Slab.TextSelectable(v) then
                components.operation = operations[i]
                self:remesh()
              end
            end

            Slab.EndComboBox()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blending")

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("blending", components.blending, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            components.blending = Slab.GetInputNumber()
            self:remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("POSITION")
        Slab.BeginLayout("position", {Columns = 2, ExpandW = true})
        local position = components.position
        local x, y, z = unpack(position)
        local step = 1 / 32

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("X", {Color = self.colors.red})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("x", x, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[1] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Y", {Color = self.colors.green})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("y", y, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[2] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Z", {Color = self.colors.blue})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("z", z, nil, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            position[3] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("ORIENTATION")
        Slab.BeginLayout("orientation", {Columns = 2, ExpandW = true})
        local orientation = components.orientation
        local qx, qy, qz, qw = unpack(orientation)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QX", {Color = self.colors.red})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qx", qx, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[1] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QY", {Color = self.colors.green})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qy", qy, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[2] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("QZ", {Color = self.colors.blue})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("qz", qz, -1, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            orientation[3] = Slab.GetInputNumber()

            orientation[1], orientation[2], orientation[3], orientation[4] =
              quaternion.normalize(unpack(orientation))

            self:remesh()
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

            self:remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("COLOR")
        Slab.BeginLayout("color", {Columns = 2, ExpandW = true})
        local color = components.color
        local red, green, blue, alpha = unpack(color)

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Red", {Color = self.colors.red})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("red", red, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[1] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Green", {Color = self.colors.green})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("green", green, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[2] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Blue", {Color = self.colors.blue})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberSlider("blue", blue, 0, 1, {
            Align = "left",
            ReturnOnText = true,
          }) then
            color[3] = Slab.GetInputNumber()
            self:remesh()
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
            self:remesh()
          end
        end

        Slab.EndLayout()
      end

      Slab.Separator()

      do
        Slab.Text("SHAPE")
        Slab.BeginLayout("shape", {Columns = 2, ExpandW = true})
        local shape = components.shape
        local width, height, depth, rounding = unpack(shape)
        local step = 1 / 32

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Width", {Color = self.colors.red})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("width", width, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[1] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Height", {Color = self.colors.green})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("height", height, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[2] = Slab.GetInputNumber()
            self:remesh()
          end
        end

        do
          Slab.SetLayoutColumn(1)
          Slab.Text("Depth", {Color = self.colors.blue})

          Slab.SetLayoutColumn(2)

          if Slab.InputNumberDrag("depth", depth, 0, nil, nil, {
            Align = "left",
            ReturnOnText = true,
            Step = step,
          }) then
            shape[3] = Slab.GetInputNumber()
            self:remesh()
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
            self:remesh()
          end
        end

        Slab.EndLayout()
      end
    end

    Slab.EndWindow()
  end

  do
    Slab.BeginWindow("status", {
      X = 0,
      Y = height - statusHeight,

      W = width - 4,
      H = statusHeight - 4,

      AllowMove = false,
      AllowResize = false,
      AutoSizeContent = true,
      AutoSizeWindow = false,
      Border = 4,
      ResetLayout = true,
      Rounding = 0,
    })

    if self.statusMessage then
      local color = self.logColors[self.statusLevel]
      Slab.Text(self.statusMessage, {Color = color})
    end

    Slab.EndWindow()
  end
end

function Editor:log(level, message)
  self.statusTimestamp = os.date('%Y-%m-%d %H:%M:%S')
  self.statusLevel = level
  self.statusMessage = message

  io.stderr:write(self.statusTimestamp .. " [" .. self.statusLevel .. "] " ..  self.statusMessage .. "\n")
end

function extendLine(x1, y1, x2, y2, r)
  local tangentX, tangentY = normalize2(x2 - x1, y2 - y1)
  return x1 - r * tangentX, y1 - r * tangentY, x2 + r * tangentX, y2 + r * tangentY
end

function Editor:draw()
  local width, height = love.graphics.getDimensions()
  local scale = 0.25

  self.viewportTransform:reset():translate(0.5 * width, 0.5 * height):scale(height)

  setRotation3(self.cameraTransform:reset(), 0, 1, 0, self.angle):apply(love.math.newTransform():setMatrix(
    scale, 0, 0, 0,
    0, scale, 0, 0,
    0, 0, scale, 0,
    0, 0, 0, 1))

  self.worldToScreenTransform:reset():apply(self.viewportTransform):apply(self.cameraTransform)
  love.graphics.setScissor(200, 0, width - 400, height)

  love.graphics.push()
  love.graphics.applyTransform(self.worldToScreenTransform)

  local transform = love.math.newTransform()

  if self.mesher == "surface-splatting" then
    if mesh then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setShader(self.shader)
      self.shader:send("ModelMatrix", transform)
      love.graphics.setMeshCullMode("back")
      love.graphics.setDepthMode("less", true)
      love.graphics.draw(mesh)
      love.graphics.setDepthMode()
      love.graphics.setMeshCullMode("none")
      love.graphics.setShader(nil)
    end
  else
    if mesh then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setShader(self.shader)
      self.shader:send("ModelMatrix", transform)
      love.graphics.setMeshCullMode("back")
      love.graphics.setDepthMode("less", true)
      love.graphics.draw(mesh)
      love.graphics.setDepthMode()
      love.graphics.setMeshCullMode("none")
      love.graphics.setShader(nil)
    end
  end

  love.graphics.pop()

  for i, instruction in ipairs(self.instructions) do
    if i == self.selection then
      local components = instruction.components

      -- TODO: Only draw wireframe lines for front faces

      local instructionTransform =
        self.worldToScreenTransform *
        setTranslation3(love.math.newTransform(), unpack(components.position)) *
        quaternion.toTransform(unpack(components.orientation))

      local width, height, depth, rounding = unpack(components.shape)

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

      love.graphics.setColor(self.colors.red)
      love.graphics.line(x1, y1, x2, y2)
      love.graphics.line(x3, y3, x4, y4)
      love.graphics.line(x5, y5, x6, y6)
      love.graphics.line(x7, y7, x8, y8)

      love.graphics.setColor(self.colors.green)
      love.graphics.line(x1, y1, x3, y3)
      love.graphics.line(x2, y2, x4, y4)
      love.graphics.line(x5, y5, x7, y7)
      love.graphics.line(x6, y6, x8, y8)

      love.graphics.setColor(self.colors.blue)
      love.graphics.line(x1, y1, x5, y5)
      love.graphics.line(x2, y2, x6, y6)
      love.graphics.line(x3, y3, x7, y7)
      love.graphics.line(x4, y4, x8, y8)
    end
  end

  love.graphics.setScissor()
  Slab.Draw()
end

function Editor:keypressed(key, scancode, isrepeat)
  if self.controller and self.controller.keypressed then
    self.controller:keypressed(key, scancode, isrepeat)
    return
  end

  -- TODO: Support e.g. control key on non-Mac
  local altDown = love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt")
  local ctrlDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
  local shiftDown = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
  local guiDown = love.keyboard.isDown("lgui") or love.keyboard.isDown("lgui")

  if guiDown and key == "p" then
    local timestamp = os.date('%Y-%m-%d-%H-%M-%S')
    local filename = "screenshot-" .. timestamp .. ".png"
    love.graphics.captureScreenshot(filename)

    self:log("info", "Captured screenshot: " .. filename)
  end

  if guiDown and key == "s" then
    if not self.modelFilename then
      self:log("error", "No model filename")
    else
      self:saveModel(self.model, self.modelFilename)
      self:log("info", "Saved model: " .. self.modelFilename)
    end
  end

  if guiDown and key == "z" then
    if shiftDown then
      if #self.commandFuture >= 1 then
        self:redoCommand()
      else
        self:log("warn", "Nothing to redo")
      end
    else
      if #self.commandHistory >= 1 then
        self:undoCommand()
      else
        self:log("warn", "Nothing to undo")
      end
    end
  end
end

function Editor:keyreleased(key, scancode)
  if self.controller and self.controller.keyreleased then
    self.controller:keyreleased(key, scancode)
    return
  end
end

function Editor:mousemoved(x, y, dx, dy, istouch)
  if self.controller and self.controller.mousemoved then
    self.controller:mousemoved(x, y, dx, dy, istouch)
    return
  end
end

function Editor:mousepressed(x, y, button, istouch, presses)
  if self.controller and self.controller.mousepressed then
    self.controller:mousepressed(x, y, button, istouch, presses)
    return
  end

  local width, height = love.graphics.getDimensions()

  if 200 < x and x <= width - 200 and 50 < y and y <= height - 50 then
    if button == 1 and self.selection then
      self.controller = MoveController.new(self)
    elseif button == 2 and self.selection then
      if love.keyboard.isDown("lalt") or love.keyboard.isDown("ralt") then
        self.controller = ScaleController.new(self)
      else
        self.controller = RotateController.new(self)
      end
    end
  end
end

function Editor:mousereleased(x, y, button, istouch, presses)
  if self.controller and self.controller.mousereleased then
    self.controller:mousereleased(x, y, button, istouch, presses)
    return
  end
end

function Editor:wheelmoved(x, y)
  if self.controller and self.controller.wheelmoved then
    self.controller:wheelmoved(x, y)
    return
  end

  self.angle = self.angle - x / 16 * pi
end

function Editor:remesh()
  self.workerInputChannel:clear()

  local minX = -2
  local minY = -2
  local minZ = -2

  local maxX = 2
  local maxY = 2
  local maxZ = 2

  if self.mesher == "dual-contouring" then
    for maxDepth = 4, 6 do
      self.workerInputVersion = self.workerInputVersion + 1

      self.workerInputChannel:push({
        version = self.workerInputVersion,
        mesher = self.mesher,
        instructions = self.instructions,

        minX = minX,
        minY = minY,
        minZ = minZ,

        maxX = maxX,
        maxY = maxY,
        maxZ = maxZ,

        maxDepth = maxDepth,
      })
    end
  else
    for maxDepth = 4, 6 do
      self.workerInputVersion = self.workerInputVersion + 1

      local instructions = {}

      for i, child in ipairs(self.model.children) do
        table.insert(instructions, child.components)
      end

      self.workerInputChannel:push({
        version = self.workerInputVersion,
        mesher = self.mesher,
        instructions = instructions,

        minX = minX,
        minY = minY,
        minZ = minZ,

        maxX = maxX,
        maxY = maxY,
        maxZ = maxZ,

        maxDepth = maxDepth,
      })
    end
  end
end

function Editor:doCommand(command)
  command:redo()
  table.insert(self.commandHistory, command)
  self.commandFuture = {}
end

function Editor:undoCommand()
  local command = table.remove(self.commandHistory)

  if not command then
    self:log("error", "Nothing to undo")
    return
  end

  command:undo()
  table.insert(self.commandFuture, command)
end

function Editor:redoCommand()
  local command = table.remove(self.commandFuture)

  if not command then
    self:log("error", "Nothing to redo")
    return
  end

  command:redo()
  table.insert(self.commandHistory, command)
end

function Editor:loadModel(filename)
  local contents, size = love.filesystem.read(filename)
  local f = assert(loadstring("return " .. contents))
  setfenv(f, {})
  local model = f()
  model.version = model.version or 1
  local oldVersion = model.version

  if model.version == 1 then
    model.children = model.instructions or {}
    model.instructions = {}

    model.version = 2
  end

  if model.version == 2 then
    for i, components in ipairs(model.children) do
      model.children[i] = {
        components = components,
      }
    end

    model.version = 3
  end

  if model.version ~= oldVersion then
    self:log("debug", "Converted model to version " .. model.version)
  end

  return model
end

function Editor:saveModel(model, filename)
  local contents = concat(dump(model, "pretty"))
  love.filesystem.write(filename, contents)
end

return Editor
