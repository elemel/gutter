local gutterMath = require("gutter.math")

local clamp = gutterMath.clamp
local length3 = gutterMath.length3
local mix = gutterMath.mix
local mix4 = gutterMath.mix4
local smoothstep = gutterMath.smoothstep

local M = {}

-- https://www.iquilezles.org/www/articles/smin/smin.htm
function M.smoothUnion(a, b, k)
  local h = clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
  return mix(b, a, h) - k * h * (1 - h)
end

function M.smoothSubtraction(d1, d2, k)
  local h = clamp(0.5 - 0.5 * (d2 + d1) / k, 0, 1)
  return mix(d2, -d1, h) + k * h * (1 - h)
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
