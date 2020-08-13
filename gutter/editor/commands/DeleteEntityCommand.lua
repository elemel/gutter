local M = {}
M.__index = M
M.title = "Delete Entity"

function M.new(editor)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.selection = assert(editor.selection)
  instance.entity = assert(editor.model.children[editor.selection])
  return instance
end

function M:redo()
  table.remove(self.editor.model.children, self.editor.selection)
  self.editor.selection = nil
  self.editor:remesh()
end

function M:undo()
  table.insert(self.editor.model.children, self.selection, self.entity)
  self.editor.selection = self.selection
  self.editor:remesh()
end

return M
