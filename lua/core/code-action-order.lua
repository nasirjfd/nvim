-- Order the aggregated LSP menu, not individual server responses: imports first,
-- documentation last, and the original order within each group.
local M = {}

local docs = {
  phpdoc = true,
  jsdoc = true,
  tsdoc = true,
  javadoc = true,
  kdoc = true,
  docblock = true,
  docstring = true,
  documentation = true,
  doc = true,
  docs = true,
}

local function priority(entry)
  local action = entry.action or entry
  local title = (action.title or ""):lower():gsub("^%s+", "")
  local kind = (action.kind or ""):lower()
  -- An import of a class named Doc/Documentation is still an import.
  if
    kind:find("import", 1, true)
    or title:match("^use%s+")
    or title:match("^import%f[%A]")
    or title:match("^add%s+imports?%f[%A]")
    or title:match("^add%s+missing%s+imports?%f[%A]")
    or title:match("^add%s+use%f[%A]")
  then
    return 1
  end
  for word in title:gmatch("%a+") do
    if docs[word] then
      return 3
    end
  end
  if kind:find("documentation", 1, true) or kind:find("docstring", 1, true) then
    return 3
  end
  return 2
end

local wrapper
local function install()
  if vim.ui.select == wrapper then
    return
  end
  local select = vim.ui.select
  wrapper = function(items, opts, on_choice)
    if not opts or opts.kind ~= "codeaction" then
      return select(items, opts, on_choice)
    end
    local order = {}
    for index, item in ipairs(items) do
      order[index] = { item = item, index = index, priority = priority(item) }
    end
    table.sort(order, function(a, b)
      return a.priority < b.priority or a.priority == b.priority and a.index < b.index
    end)
    local sorted = {}
    for index, entry in ipairs(order) do
      sorted[index] = entry.item
    end
    return select(sorted, opts, function(item, index)
      on_choice(item, index and order[index].index or nil)
    end)
  end
  vim.ui.select = wrapper
end

function M.setup()
  install()
  -- Snacks installs its select backend on UIEnter, after core startup.
  vim.api.nvim_create_autocmd("UIEnter", {
    group = vim.api.nvim_create_augroup("CodeActionOrder", { clear = true }),
    once = true,
    callback = install,
  })
end

return M
