local gutterMath = require("gutter.math")
local MoveCommand = require("gutter.editor.commands.MoveCommand")
local quaternion = require("gutter.quaternion")

local atan2 = math.atan2
local normalize3 = gutterMath.normalize3
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
  instance.oldPosition = {unpack(entity.components.position)}
  instance.newPosition = {unpack(entity.components.position)}

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

    local screenDx = x - self.startScreenX
    local screenDy = y - self.startScreenY

    local x, y, z = unpack(self.oldPosition)
    local worldDx, worldDy, worldDz = transformVector3(screenToWorldTransform, screenDx, screenDy, 0)

    local entity = self.editor.model.children[self.editor.selection]
    entity.components.position = {x + worldDx, y + worldDy, z + worldDz}
    self.newPosition = {x + worldDx, y + worldDy, z + worldDz}

    self.editor:remesh()
  end
end

function M:mousereleased(x, y, button, istouch, presses)
  self.editor:doCommand(MoveCommand.new(self.editor, self.oldPosition, self.newPosition))
  self:destroy()
end

return M
