local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local sub = string.sub

local M = {}

-- https://en.wikipedia.org/wiki/Quaternions_and_spatial_rotation#The_conjugation_operation
function M.conjugate(x, y, z, w)
  return -x, -y, -z, w
end

-- https://www.euclideanspace.com/maths/geometry/rotations/conversions/angleToQuaternion/index.htm
function M.fromAxisAngle(ax, ay, az, angle)
  local qx = ax * sin(0.5 * angle)
  local qy = ay * sin(0.5 * angle)
  local qz = az * sin(0.5 * angle)

  local qw = cos(0.5 * angle)

  return qx, qy, qz, qw
end

function M.normalize(x, y, z, w)
  local length = sqrt(x * x + y * y + z * z + w * w)
  return x / length, y / length, z / length, w / length, length
end

local axisVectors = {
  x = {1, 0, 0},
  y = {0, 1, 0},
  z = {0, 0, 1},
}

function M.fromEulerAngles(axes, ...)
  local qx = 0
  local qy = 0
  local qz = 0
  local qw = 1

  for i = 1, #axes do
    local axis = sub(axes, i, i)
    local axisVector = assert(axisVectors[axis], "Invalid axis")
    local ax, ay, az = unpack(axisVector)
    local angle = select(i, ...)

    qx, qy, qz, qw = M.product(
      qx, qy, qz, qw, M.fromAxisAngle(ax, ay, az, angle))
  end

  return qx, qy, qz, qw
end

-- https://en.wikipedia.org/wiki/Quaternion#Hamilton_product
function M.product(qx1, qy1, qz1, qw1, qx2, qy2, qz2, qw2)
  local qx = qw1 * qx2 + qx1 * qw2 + qy1 * qz2 - qz1 * qy2
  local qy = qw1 * qy2 - qx1 * qz2 + qy1 * qw2 + qz1 * qx2
  local qz = qw1 * qz2 + qx1 * qy2 - qy1 * qx2 + qz1 * qw2
  local qw = qw1 * qw2 - qx1 * qx2 - qy1 * qy2 - qz1 * qz2

  return qx, qy, qz, qw
end

-- https://en.wikipedia.org/wiki/Quaternions_and_spatial_rotation#Using_quaternion_as_rotations
function M.rotate(qx, qy, qz, qw, x, y, z)
  local qx2, qy2, qz2, qw2 = M.product(qx, qy, qz, qw, x, y, z, 0)
  local x2, y2, z2 = M.product(qx2, qy2, qz2, qw2, M.conjugate(qx, qy, qz, qw))
  return x2, y2, z2
end

function M.inverseRotate(qx, qy, qz, qw, x, y, z)
  local qx2, qy2, qz2, qw2 = M.conjugate(qx, qy, qz, qw)
  return M.rotate(qx2, qy2, qz2, qw2, x, y, z)
end

return M
