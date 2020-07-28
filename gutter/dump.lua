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

function M.dumpTable(buffer, t, pretty, depth, stack)
  if stack[t] then
    table.insert(buffer, "(")
    table.insert(buffer, tostring(stack[t]))
    table.insert(buffer, ")")
    return
  end

  table.insert(stack, t)
  stack[t] = #stack
  local first = true
  local blank1 = false
  local blank2 = false
  table.insert(buffer, "{")

  for i, element in ipairs(t) do
    blank2 = type(element) == "table" and not stack[element]

    if first then
      if pretty then
        table.insert(buffer, "\n")

        for j = 1, depth + 1 do
          table.insert(buffer, "  ")
        end
      end
    else
      if pretty then
        if blank1 or blank2 then
          table.insert(buffer, "\n")
        end

        for j = 1, depth + 1 do
          table.insert(buffer, "  ")
        end
      else
        table.insert(buffer, ",")
      end
    end

    M.dumpValue(buffer, element, pretty, depth + 1, stack)

    if pretty then
        table.insert(buffer, ",\n")
    end

    first = false
    blank1 = blank2
  end

  for name, element in pairs(t) do
    local isArrayIndex = type(name) == "number" and name <= #t
    local isMetamethodName = type(name) == "string" and string.sub(name, 1, 2) == "__"

    if not isArrayIndex and not isMetamethodName then
      blank2 = type(element) == "table" and not stack[element]

      if first then
        if pretty then
          table.insert(buffer, "\n")

          for j = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        end
      else
        if pretty then
          if blank1 or blank2 then
            table.insert(buffer, "\n")
          end

          for j = 1, depth + 1 do
            table.insert(buffer, "  ")
          end
        else
          table.insert(buffer, ",")
        end
      end

      if type(name) == "string" and
          string.find(name, "^[%a_][%w_]*$") and
          not keywords[name] then

        table.insert(buffer, name)
      else
        table.insert(buffer, "[")
        M.dumpValue(buffer, name, pretty, depth + 1, stack)
        table.insert(buffer, "]")
      end

      if pretty then
        table.insert(buffer, " = ")
      else
        table.insert(buffer, "=")
      end

      M.dumpValue(buffer, element, pretty, depth + 1, stack)

      if pretty then
          table.insert(buffer, ",\n")
      end

      first = false
      blank1 = blank2
    end
  end

  if not first and pretty then
    for j = 1, depth do
      table.insert(buffer, "  ")
    end
  end

  table.insert(buffer, "}")
  stack[t] = nil
  assert(table.remove(stack) == t)
end

function M.dumpValue(buffer, value, pretty, depth, stack)
  if type(value) == "string" then
    table.insert(buffer, string.format("%q", value))
  elseif type(value) == "table" then
    M.dumpTable(buffer, value, pretty, depth, stack)
  else
    table.insert(buffer, tostring(value))
  end
end

function M.dump(value, format, buffer)
  format = format or "compact"
  assert(format == "compact" or format == "pretty", "Invalid format")
  buffer = buffer or {}
  M.dumpValue(buffer, value, format == "pretty", 0, {})
  return buffer
end

return M
