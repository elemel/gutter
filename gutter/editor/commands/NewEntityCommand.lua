local M = {}
M.__index = M
M.title = "New Entity"

function M.new(editor)
  local instance = setmetatable({}, M)
  instance.editor = assert(editor)
  return instance
end

function M:redo()
  table.insert(self.editor.model.children, {
    components = {
      operation = "union",
      blending = 0,

      position = {0, 0, 0},
      orientation = {0, 0, 0, 1},

      color = {0.5, 0.5, 0.5, 1},
      shape = {1, 1, 1, 1},
    },
  })

  self.editor.selection = #self.editor.model.children
  self.editor:remesh()
end

function M:undo()
  table.remove(self.editor.model.children)
  self.editor.selection = nil -- TODO: Update selection
  self.editor:remesh()
end

return M
