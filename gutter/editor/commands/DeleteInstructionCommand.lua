local M = {}
M.__index = M
M.title = "Delete Instruction"

function M.new(editor)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.selection = assert(editor.selection)
  instance.instruction = assert(editor.instructions[editor.selection])
  return instance
end

function M:redo()
  table.remove(self.editor.instructions, self.editor.selection)
  self.editor.selection = nil
  self.editor:remesh()
end

function M:undo()
  table.insert(self.editor.instructions, self.selection, self.instruction)
  self.editor.selection = self.selection
  self.editor:remesh()
end

return M
