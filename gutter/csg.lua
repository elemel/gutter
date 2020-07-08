local gutterMath = require("gutter.math")

local abs = math.abs
local clamp = gutterMath.clamp
local length3 = gutterMath.length3
local max = math.max
local min = math.min
local mix = gutterMath.mix
local mix4 = gutterMath.mix4
local smoothstep = gutterMath.smoothstep

local M = {}

function M.smoothUnion(a, b, k)
  local h = min(max(1 - abs(a - b) / k, 0), 1)
  return min(a, b) - 0.25 * h * h * k
end

function M.smoothSubtraction(a, b, k)
  local h = min(max(1 - abs(a + b) / k, 0), 1)
  return max(-a, b) + 0.25 * h * h * k
end

function M.smoothUnionColor(ad, ar, ag, ab, aa, bd, br, bg, bb, ba, k)
  local d = M.smoothUnion(ad, bd, k)
  local t = smoothstep(-k, k, ad - bd);
  return d, mix4(ar, ag, ab, aa, br, bg, bb, ba, t)
end

function M.smoothSubtractionColor(ad, ar, ag, ab, aa, bd, br, bg, bb, ba, k)
  local d = M.smoothSubtraction(ad, bd, k)
  local t = smoothstep(-k, k, bd + ad);
  return d, mix4(ar, ag, ab, aa, br, bg, bb, ba, t)
end

function M.sphere(x, y, z, radius)
  return length3(x, y, z) - radius
end

return M
