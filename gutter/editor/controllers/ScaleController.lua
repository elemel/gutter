local gutterMath = require("gutter.math")

local distance2 = gutterMath.distance2
local normalize3 = gutterMath.normalize3
local ScaleInstructionCommand = require("gutter.editor.commands.ScaleInstructionCommand")
local setRotation3 = gutterMath.setRotation3
local transformPoint3 = gutterMath.transformPoint3
local transformVector3 = gutterMath.transformVector3

local M = {}
M.__index = M

function M.new(editor)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.editor.controller = instance

  instance.startScreenX, instance.startScreenY = love.mouse.getPosition()

  local selection = assert(editor.selection)
  local instruction = assert(editor.instructions[selection])

  instance.oldShape = {unpack(instruction.shape)}
  instance.newShape = {unpack(instruction.shape)}

  return instance
end

function M:destroy()
  self.editor.controller = nil
end

function M:mousemoved(x, y, dx, dy, istouch)
  self:updateInstruction()
end

function M:updateInstruction()
  local x, y = love.mouse.getPosition()

  if self.editor.selection then
    -- TODO: Use camera and viewport transforms kept in sync elsewhere

    local width, height = love.graphics.getDimensions()
    local scale = 0.25

    local viewportTransform = love.math.newTransform():translate(0.5 * width, 0.5 * height):scale(height)

    local cameraTransform = setRotation3(love.math.newTransform(), 0, 1, 0, self.editor.angle):apply(love.math.newTransform():setMatrix(
      scale, 0, 0, 0,
      0, scale, 0, 0,
      0, 0, scale, 0,
      0, 0, 0, 1))

    local worldToScreenTransform = love.math.newTransform():apply(viewportTransform):apply(cameraTransform)
    local screenToWorldTransform = worldToScreenTransform:inverse()

    local instruction = self.editor.instructions[self.editor.selection]

    local width, height, depth, rounding = unpack(self.oldShape)

    local pivotX, pivotY = transformPoint3(worldToScreenTransform, unpack(instruction.position))
    local startDistance = distance2(pivotX, pivotY, self.startScreenX, self.startScreenY)
    local distance = distance2(pivotX, pivotY, x, y)
    local scale = distance / startDistance

    instruction.shape = {scale * width, scale * height, scale * depth, rounding}
    self.newShape = {unpack(instruction.shape)}

    self.editor:remesh()
  end
end

function M:mousereleased(x, y, button, istouch, presses)
  self.editor:doCommand(ScaleInstructionCommand.new(self.editor, self.oldShape, self.newShape))
  self:destroy()
end

return M
