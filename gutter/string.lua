local M = {}

function M.capitalize(s)
  s = s:gsub("^%l", upper)
  return s
end

return M
