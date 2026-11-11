-- PHPUnit's junit log (as parsed by neotest.lib.xml) -> neotest results, keyed by position id
-- ("<file>::<method>", the ids olimorris/neotest-phpunit gives the tests it finds).
--
-- Written here instead of reusing neotest-phpunit's reader, which crashes on a log with a testcase that has
-- no `file` (PHPUnit writes one for a class whose setUpBeforeClass fails) and then loses the whole run.
local M = {}

local function list(value)
  if type(value) ~= "table" then
    return {}
  end
  if value._attr ~= nil or value[1] == nil then
    return { value } -- a single element
  end
  return value
end

local function text_of(element)
  if type(element) == "string" then
    return element
  end
  if type(element) == "table" then
    for _, part in ipairs(element) do
      if type(part) == "string" then
        return part
      end
    end
    return element._attr and element._attr.message or ""
  end
  return ""
end

-- the first failure of a testcase: kind ("error"/"failure"/"warning"/"skipped") and its text
local function problem(case)
  for _, kind in ipairs({ "error", "failure", "warning" }) do
    local found = case[kind]
    if found ~= nil then
      return kind, text_of(list(found)[1])
    end
  end
  if case.skipped ~= nil then
    return "skipped", text_of(list(case.skipped)[1])
  end
end

local function walk(node, file, out)
  if type(node) ~= "table" then
    return
  end
  local own = node._attr and node._attr.file or file
  for key, value in pairs(node) do
    if key == "testcase" then
      for _, case in ipairs(list(value)) do
        table.insert(out, { case = case, file = case._attr and case._attr.file or own })
      end
    elseif key ~= "_attr" and type(value) == "table" then
      walk(value, own, out)
    end
  end
end

local function status_of_case(kind)
  return (kind == "skipped") and "skipped" or kind and "failed" or "passed"
end

--- The results of a parsed junit log, one per test method. A method with a data provider runs once per data set:
--- its result has `datasets` ({ label, status, short?, errors? } in the order of the log, label as PHPUnit
--- names it: `#3` or `"name"`), its own status is failed when any data set failed.
---@param parsed table
---@return table<string, { status: string, short: string, errors?: table[], datasets?: table[] }>
function M.results(parsed)
  local cases = {}
  walk(parsed, nil, cases)
  local results = {}
  for _, entry in ipairs(cases) do
    local attr = entry.case._attr or {}
    -- "Class::method" (no file attribute) or "method with data set #1"
    -- (the label of a data set may have colons in it: split off the label first)
    local name = attr.name or ""
    local method, label = name:match("^(.-) with data set (.*)$")
    method = (method or name):match("([^:]+)$") or ""
    local file = entry.file
    if file and method ~= "" then
      local id = file .. "::" .. method
      local kind, message = problem(entry.case)
      local status = status_of_case(kind)
      local detail = { status = status, short = kind and (message:match("[^\n]*\n?[^\n]*") or message) or "passed" }
      if status == "failed" then
        local errors = {}
        for line_file, line in message:gmatch("([^%s:]+%.php):(%d+)") do
          if line_file == file then
            errors[#errors + 1] = { line = tonumber(line) - 1, message = message }
          end
        end
        if #errors == 0 and tonumber(attr.line) then
          errors[1] = { line = tonumber(attr.line) - 1, message = message }
        end
        detail.errors = errors
      end
      local result = results[id]
      if not result then
        result = { status = status, short = detail.short, errors = detail.errors }
        results[id] = result
      elseif status == "failed" and result.status ~= "failed" then
        -- one failing data set fails the method; its message is the first failure
        result.status, result.short, result.errors = "failed", detail.short, detail.errors
      elseif status == "passed" and result.status == "skipped" then
        result.status = "passed"
      end
      if label then
        result.datasets = result.datasets or {}
        table.insert(result.datasets, { label = label, status = status, short = detail.short, errors = detail.errors })
      end
    end
  end
  return results
end

--- Parse junit text and give its results.
function M.from_text(text)
  local parsed = require("neotest.lib").xml.parse(text)
  return M.results(parsed)
end

return M
