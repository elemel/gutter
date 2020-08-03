local loveMath = require("love.math")

local abs = math.abs
local cos = math.cos
local floor = math.floor
local max = math.max
local min = math.min
local modf = math.modf
local sin = math.sin
local sqrt = math.sqrt

local M = {}

function M.clamp(x, minX, maxX)
  return min(max(x, minX), maxX)
end

function M.cross(ax, ay, az, bx, by, bz)
  return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

function M.distance2(x1, y1, x2, y2)
  local dx = x2 - x1
  local dy = y2 - y1

  return sqrt(dx * dx + dy * dy)
end

function M.distance3(x1, y1, z1, x2, y2, z2)
  local dx = x2 - x1
  local dy = y2 - y1
  local dz = z2 - z1

  return sqrt(dx * dx + dy * dy + dz * dz)
end

function M.dot3(x1, y1, z1, x2, y2, z2)
  return x1 * x2 + y1 * y2 + z1 * z2
end

function M.length3(x, y, z)
  return sqrt(x * x + y * y + z * z)
end

function M.mix(a, b, t)
  return (1 - t) * a + t * b
end

function M.mix3(ax, ay, az, bx, by, bz, tx, ty, tz)
  ty = ty or tx
  tz = tz or tx

  local x = (1 - tx) * ax + tx * bx
  local y = (1 - ty) * ay + ty * by
  local z = (1 - tz) * az + tz * bz

  return x, y, z
end

function M.mix4(ax, ay, az, aw, bx, by, bz, bw, tx, ty, tz, tw)
  ty = ty or tx
  tz = tz or tx
  tw = tw or tx

  local x = (1 - tx) * ax + tx * bx
  local y = (1 - ty) * ay + ty * by
  local z = (1 - tz) * az + tz * bz
  local w = (1 - tw) * aw + tw * bw

  return x, y, z, w
end

function M.normalize2(x, y)
  local length = sqrt(x * x + y * y)
  return x / length, y / length, length
end

function M.normalize3(x, y, z)
  local length = sqrt(x * x + y * y + z * z)
  return x / length, y / length, z / length, length
end

function M.perp(x, y, z)
  if abs(x) < abs(y) then
    if abs(y) < abs(z) then
      return 0, -z, y
    elseif abs(x) < abs(z) then
      return 0, z, -y
    else
      return -y, x, 0
    end
  else
    if abs(z) < abs(y) then
      return y, -x, 0
    elseif abs(z) < abs(x) then
      return z, 0, -x
    else
      return -z, 0, x
    end
  end
end

function M.round3(x, y, z)
  return floor(x + 0.5), floor(y + 0.5), floor(z + 0.5)
end

-- https://en.wikipedia.org/wiki/Rotation_matrix#Rotation_matrix_from_axis_and_angle
function M.setRotation3(t, axisX, axisY, axisZ, angle)
  local t11, t12, t13, t14,
    t21, t22, t23, t24,
    t31, t32, t33, t34,
    t41, t42, t43, t44 = t:getMatrix()

  local cosAngle = cos(angle)
  local sinAngle = sin(angle)

  t11 = cosAngle + axisX * axisX * (1 - cosAngle)
  t12 = axisX * axisY * (1 - cosAngle) - axisZ * sinAngle
  t13 = axisX * axisZ * (1 - cosAngle) + axisY * sinAngle

  t21 = axisY * axisX * (1 - cosAngle) + axisZ * sinAngle
  t22 = cosAngle + axisY * axisY * (1 - cosAngle)
  t23 = axisY * axisZ * (1 - cosAngle) - axisX * sinAngle

  t31 = axisZ * axisX * (1 - cosAngle) - axisY * sinAngle
  t32 = axisZ * axisY * (1 - cosAngle) + axisX * sinAngle
  t33 = cosAngle + axisZ * axisZ * (1 - cosAngle)

  t:setMatrix(t11, t12, t13, t14,
    t21, t22, t23, t24,
    t31, t32, t33, t34,
    t41, t42, t43, t44)

  return t
end

function M.setTranslation3(t, x, y, z)
  local t11, t12, t13, t14,
    t21, t22, t23, t24,
    t31, t32, t33, t34,
    t41, t42, t43, t44 = t:getMatrix()

  t:setMatrix(t11, t12, t13, x,
    t21, t22, t23, y,
    t31, t32, t33, z,
    t41, t42, t43, t44)

  return t
end

function M.smoothstep(x1, x2, x)
    x = min(max((x - x1) / (x2 - x1), 0), 1)
    return x * x * (3 - 2 * x)
end

function M.squaredDistance3(x1, y1, z1, x2, y2, z2)
  return (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) + (z2 - z1) * (z2 - z1)
end

function M.transformPoint3(t, x, y, z)
  local t11, t12, t13, t14,
    t21, t22, t23, t24,
    t31, t32, t33, t34,
    t41, t42, t43, t44 = t:getMatrix()

  local tx = t11 * x + t12 * y + t13 * z + t14
  local ty = t21 * x + t22 * y + t23 * z + t24
  local tz = t31 * x + t32 * y + t33 * z + t34

  return tx, ty, tz
end

function M.transformVector3(t, x, y, z)
  local t11, t12, t13, t14,
    t21, t22, t23, t24,
    t31, t32, t33, t34,
    t41, t42, t43, t44 = t:getMatrix()

  local tx = t11 * x + t12 * y + t13 * z
  local ty = t21 * x + t22 * y + t23 * z
  local tz = t31 * x + t32 * y + t33 * z

  return tx, ty, tz
end

function M.translate3(t, x, y, z)
  return t:apply(loveMath.newTransform():setMatrix(1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1))
end

return M
