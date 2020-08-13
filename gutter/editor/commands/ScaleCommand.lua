local M = {}
M.__index = M
M.title = "Scale"

function M.new(editor, oldShape, newShape)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.oldShape = {unpack(oldShape)}
  instance.newShape = {unpack(newShape)}

  local selection = assert(editor.selection)
  instance.entity = assert(editor.model.children[selection])
  return instance
end

function M:redo()
  self.entity.components.shape = {unpack(self.newShape)}
  self.editor:remesh()
end

function M:undo()
  self.entity.components.shape = {unpack(self.oldShape)}
  self.editor:remesh()
end

return M
