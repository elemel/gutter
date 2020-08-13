local M = {}
M.__index = M
M.title = "Rotate"

function M.new(editor, oldOrientation, newOrientation)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  instance.oldOrientation = {unpack(oldOrientation)}
  instance.newOrientation = {unpack(newOrientation)}

  local selection = assert(editor.selection)
  instance.entity = assert(editor.model.children[selection])
  return instance
end

function M:redo()
  self.entity.components.orientation = {unpack(self.newOrientation)}
  self.editor:remesh()
end

function M:undo()
  self.entity.components.orientation = {unpack(self.oldOrientation)}
  self.editor:remesh()
end

return M
