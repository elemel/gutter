local M = {}
M.__index = M
M.title = "Move Instruction"

function M.new(editor, oldPosition, newPosition)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.oldPosition = {unpack(oldPosition)}
  instance.newPosition = {unpack(newPosition)}

  local selection = assert(editor.selection)
  instance.instruction = assert(editor.instructions[selection])
  return instance
end

function M:redo()
  self.instruction.position = {unpack(self.newPosition)}
  self.editor:remesh()
end

function M:undo()
  self.instruction.position = {unpack(self.oldPosition)}
  self.editor:remesh()
end

return M
