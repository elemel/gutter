local max = math.max
local min = math.min

local M = {}

function M.mix(a, b, t)
  return (1 - t) * a + t * b
end

function M.clamp(x, x1, x2)
  return min(max(x, x1), x2)
end

return M
