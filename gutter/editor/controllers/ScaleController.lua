local gutterMath = require("gutter.math")

local distance2 = gutterMath.distance2
local normalize3 = gutterMath.normalize3
local ScaleCommand = require("gutter.editor.commands.ScaleCommand")
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
  local entity = assert(editor.model.children[selection])

  instance.oldShape = {unpack(entity.components.shape)}
  instance.newShape = {unpack(entity.components.shape)}

  return instance
end

function M:destroy()
  self.editor.controller = nil
end

function M:mousemoved(x, y, dx, dy, istouch)
  if self.editor.selection then
    -- TODO: Use camera and viewport transforms kept in sync elsewhere

    local x, y = love.mouse.getPosition()

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

    local entity = self.editor.model.children[self.editor.selection]

    local width, height, depth, rounding = unpack(self.oldShape)

    local pivotX, pivotY = transformPoint3(worldToScreenTransform, unpack(entity.components.position))
    local startDistance = distance2(pivotX, pivotY, self.startScreenX, self.startScreenY)
    local distance = distance2(pivotX, pivotY, x, y)
    local scale = distance / startDistance

    entity.components.shape = {scale * width, scale * height, scale * depth, rounding}
    self.newShape = {unpack(entity.components.shape)}

    self.editor:remesh()
  end
end

function M:mousereleased(x, y, button, istouch, presses)
  self.editor:doCommand(ScaleCommand.new(self.editor, self.oldShape, self.newShape))
  self:destroy()
end

return M
