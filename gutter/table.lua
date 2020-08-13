local M = {}

function M.clear(t)
  for k in pairs(t) do
    t[k] = nil
  end
end

function M.find(t, v)
  for k, v2 in pairs(t) do
    if v2 == v then
      return k
    end
  end

  return nil
end

return M
