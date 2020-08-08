local gutterMath = require("gutter.math")
local quaternion = require("gutter.quaternion")

local abs = math.abs
local clamp = gutterMath.clamp
local inverseRotate = quaternion.inverseRotate
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

-- https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm
function M.box(px, py, pz, bx, by, bz)
  local qx = abs(px) - bx
  local qy = abs(py) - by
  local qz = abs(pz) - bz

  return length3(max(qx, 0), max(qy, 0), max(qz, 0)) + min(max(qx, qy, qz), 0)
end

function M.getInstructionDistanceAndBlendRangeForPoint(instruction, x, y, z)
  local positionX, positionY, positionZ = unpack(instruction.position)
  local qx, qy, qz, qw = unpack(instruction.orientation)

  local instructionRed, instructionGreen, instructionBlue, instructionAlpha = unpack(instruction.color)
  local width, height, depth, rounding = unpack(instruction.shape)
  local maxRadius = 0.5 * min(width, height, depth)
  local radius = rounding * maxRadius
  local blendRange = instruction.blending * maxRadius

  local instructionX, instructionY, instructionZ = inverseRotate(
    qx, qy, qz, qw, x - positionX, y - positionY, z - positionZ)

  local instructionDistance = M.box(
    instructionX, instructionY, instructionZ,
    0.5 * width - radius, 0.5 * height - radius, 0.5 * depth - radius) - radius

  return instructionDistance, blendRange
end

function M.applyInstructionsToPoint(instructions, x, y, z)
  local distance = huge

  local red = 0
  local green = 0
  local blue = 0
  local alpha = 0

  for _, instruction in ipairs(instructions) do
    local positionX, positionY, positionZ = unpack(instruction.position)
    local qx, qy, qz, qw = unpack(instruction.orientation)

    local instructionRed, instructionGreen, instructionBlue, instructionAlpha = unpack(instruction.color)
    local width, height, depth, rounding = unpack(instruction.shape)
    local maxRadius = 0.5 * min(width, height, depth)
    local radius = rounding * maxRadius
    local blendRange = instruction.blending * maxRadius

    local instructionX, instructionY, instructionZ = inverseRotate(
      qx, qy, qz, qw,
      x - positionX, y - positionY, z - positionZ)

    local instructionDistance = box(
      instructionX, instructionY, instructionZ,
      0.5 * width - radius, 0.5 * height - radius, 0.5 * depth - radius) - radius

    if instruction.operation == "union" then
      distance, red, green, blue, alpha =
        smoothUnionColor(
          distance, red, green, blue, alpha,
          instructionDistance, instructionRed, instructionGreen, instructionBlue, instructionAlpha,
          blendRange)
    elseif instruction.operation == "subtraction" then
      distance, red, green, blue, alpha =
        smoothSubtractionColor(
          instructionDistance, instructionRed, instructionGreen, instructionBlue, instructionAlpha,
          distance, red, green, blue, alpha,
          blendRange)
    else
      assert("Invalid operation")
    end
  end
end

return M
