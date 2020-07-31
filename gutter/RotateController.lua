local gutterMath = require("gutter.math")
local quaternion = require("gutter.quaternion")

local atan2 = math.atan2
local normalize3 = gutterMath.normalize3
local setRotation3 = gutterMath.setRotation3
local transformPoint3 = gutterMath.transformPoint3
local transformVector3 = gutterMath.transformVector3

local M = {}
M.__index = M

function M.new(editor, x, y)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.editor.controller = instance

  instance.startScreenX = x
  instance.startScreenY = y

  local selection = assert(editor.selection)
  local instruction = assert(editor.instructions[selection])
  instance.startOrientation = {unpack(instruction.orientation)}

  return instance
end

function M:destroy()
  self.editor.controller = nil
end

function M:mousemoved(x, y, dx, dy, istouch)
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

    local axisX, axisY, axisZ = normalize3(transformVector3(screenToWorldTransform, 0, 0, 1))

    local instruction = self.editor.instructions[self.editor.selection]

    -- TODO: Use pivot based on selection or camera
    local pivotX, pivotY = transformPoint3(worldToScreenTransform, unpack(instruction.position))
    local angle1 = atan2(self.startScreenY - pivotY, self.startScreenX - pivotX)
    local angle2 = atan2(y - pivotY, x - pivotX)
    local angle = angle2 - angle1

    local qx1, qy1, qz1, qw1 = unpack(self.startOrientation)

    local qx2, qy2, qz2, qw2 = quaternion.fromAxisAngle(axisX, axisY, axisZ, angle)

    instruction.orientation = {quaternion.product(qx2, qy2, qz2, qw2, qx1, qy1, qz1, qw1)}
    self.editor:remesh()
  end
end

function M:mousereleased(x, y, button, istouch, presses)
  self:destroy()
end

return M
