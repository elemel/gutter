--[[

MIT License

Copyright (c) 2020 Mikael Lind

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]]

local M = {}

local keywords = {
  ["and"] = true,
  ["break"] = true,
  ["do"] = true,
  ["else"] = true,
  ["elseif"] = true,
  ["end"] = true,
  ["false"] = true,
  ["for"] = true,
  ["function"] = true,
  ["if"] = true,
  ["in"] = true,
  ["local"] = true,
  ["nil"] = true,
  ["not"] = true,
  ["or"] = true,
  ["repeat"] = true,
  ["return"] = true,
  ["then"] = true,
  ["true"] = true,
  ["until"] = true,
  ["while"] = true,
}

-- Dump a Lua value to a buffer. The concatenated result can be parsed as Lua
-- code. The supported types are nil, boolean, number, string and table (not
-- cyclic). The supported formats are "compact" (default) and "pretty" for
-- pretty-printing. The order parameter is a function for comparing table keys.
-- The default order handles number and string keys (not mixed).
function M.dump(value, format, order, buffer, depth, stack)
  format = format or "compact"
  assert(format == "compact" or format == "pretty", "Invalid format")

  buffer = buffer or {}
  depth = depth or 0

  if type(value) == "nil" or
    type(value) == "boolean" or
    type(value) == "number" then

    table.insert(buffer, tostring(value))
  elseif type(value) == "string" then
    table.insert(buffer, string.format("%q", value))
  elseif type(value) == "table" then
    stack = stack or {}
    local pretty = format == "pretty"

    if stack[value] then
      table.insert(buffer, "<")
      table.insert(buffer, tostring(stack[value]))
      table.insert(buffer, ">")
      return
    end

    table.insert(stack, value)
    stack[value] = #stack
    local first = true

    local blank1 = false
    local blank2 = false

    table.insert(buffer, "{")

    for _, element in ipairs(value) do
      blank2 =
        type(element) == "table" and
        not stack[element] and
        next(element) ~= nil

      if first then
        if pretty then
          table.insert(buffer, "\n")

          for _ = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        end
      else
        if pretty then
          if blank1 or blank2 then
            table.insert(buffer, "\n")
          end

          for _ = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        else
          table.insert(buffer, ",")
        end
      end

      M.dump(element, format, order, buffer, depth + 1, stack)

      if pretty then
        table.insert(buffer, ",\n")
      end

      first = false
      blank1 = blank2
    end

    local keys = {}

    for key in pairs(value) do
      local isArrayIndex =
        type(key) == "number" and
        key == math.floor(key) and
        key >= 1 and
        key <= #value

      local isMetamethodName =
        type(key) == "string" and
        string.sub(key, 1, 2) == "__"

      if not isArrayIndex and not isMetamethodName then
        table.insert(keys, key)
      end
    end

    table.sort(keys, order)

    for _, key in ipairs(keys) do
      local element = value[key]
      blank2 =
        type(element) == "table" and
        not stack[element] and
        next(element) ~= nil

      if first then
        if pretty then
          table.insert(buffer, "\n")

          for _ = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        end
      else
        if pretty then
          if blank1 or blank2 then
            table.insert(buffer, "\n")
          end

          for _ = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        else
          table.insert(buffer, ",")
        end
      end

      if type(key) == "string" and
          string.find(key, "^[%a_][%w_]*$") and
          not keywords[key] then

        table.insert(buffer, key)
      else
        table.insert(buffer, "[")
        M.dump(key, format, order, buffer, depth + 1, stack)
        table.insert(buffer, "]")
      end

      if pretty then
        table.insert(buffer, " = ")
      else
        table.insert(buffer, "=")
      end

      M.dump(element, format, order, buffer, depth + 1, stack)

      if pretty then
          table.insert(buffer, ",\n")
      end

      first = false
      blank1 = blank2
    end

    if not first and pretty then
      for _ = 1, depth do
        table.insert(buffer, "  ")
      end
    end

    table.insert(buffer, "}")
    stack[value] = nil
    assert(table.remove(stack) == value)
  else
    table.insert(buffer, "<")
    table.insert(buffer, type(value))
    table.insert(buffer, ">")
  end

  return buffer
end

return M
