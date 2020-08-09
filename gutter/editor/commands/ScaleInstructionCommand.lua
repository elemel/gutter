local M = {}
M.__index = M
M.title = "Scale Instruction"

function M.new(editor, oldShape, newShape)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.oldShape = {unpack(oldShape)}
  instance.newShape = {unpack(newShape)}

  local selection = assert(editor.selection)
  instance.instruction = assert(editor.instructions[selection])
  return instance
end

function M:redo()
  self.instruction.components.shape = {unpack(self.newShape)}
  self.editor:remesh()
end

function M:undo()
  self.instruction.components.shape = {unpack(self.oldShape)}
  self.editor:remesh()
end

return M
