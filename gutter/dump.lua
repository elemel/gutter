local floor = math.floor
local format = string.format
local insert = table.insert
local match = string.match

local M = {}

function M.dump(v, buffer)
  buffer = buffer or {}
  local t = type(v)

  if t == "boolean" or t == "number" then
    insert(buffer, tostring(v))
  elseif t == "string" then
    insert(buffer, format("%q", v))
  elseif t == "table" then
    local first = true
    insert(buffer, "{")

    for _, v2 in ipairs(v) do
      if not first then
        insert(buffer, ", ")
      end

      M.dump(v2, buffer)
      first = false
    end

    for k, v2 in pairs(v) do
      local t2 = type(k)

      if t2 ~= "number" or floor(k) ~= k or k < 1 or k > #v then
        if not first then
          insert(buffer, ", ")
        end

        if t2 == "string" and match(t2, "^[_%a][_%w]*$") then
          insert(buffer, k)
        else
          insert(buffer, "[")
          M.dump(k, buffer)
          insert(buffer, "]")
        end

        insert(buffer, " = ")
        M.dump(v2, buffer)
        first = false
      end
    end

    insert(buffer, "}")
  end

  return buffer
end

return M
