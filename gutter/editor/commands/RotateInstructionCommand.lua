local M = {}
M.__index = M
M.title = "Rotate Instruction"

function M.new(editor, oldOrientation, newOrientation)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.oldOrientation = {unpack(oldOrientation)}
  instance.newOrientation = {unpack(newOrientation)}

  local selection = assert(editor.selection)
  instance.instruction = assert(editor.instructions[selection])
  return instance
end

function M:redo()
  self.instruction.components.orientation = {unpack(self.newOrientation)}
  self.editor:remesh()
end

function M:undo()
  self.instruction.components.orientation = {unpack(self.oldOrientation)}
  self.editor:remesh()
end

return M
