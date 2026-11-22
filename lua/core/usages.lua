-- The usages of a declaration, at once. `gd` on a declaration lists its usages, and a language server can take
-- seconds for them (intelephense: ~3.5 s for a method named `create`, every time). So:
--   * while the cursor rests on the name of a declaration (treesitter, no request), its usages are asked for in the
--     background and kept for that exact text of the buffer: `gd` then shows them without waiting;
--   * when they are not there yet, the list opens right away (loading) and fills in when the server answers;
--     a single usage is opened directly, like before.
local M = {}

local api = vim.api
local METHOD = "textDocument/references"
local MAX = 16 -- answers kept
local TTL = 60 * 1000 -- ms: other files change too

local entries = {} ---@type table<string, table>
local order = {} ---@type string[]

--- The name node of the declaration whose name is at (row, col) (0-based), or nil.
function M.declaration_name(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
  if not ok or not node or node:named_child_count() > 0 then
    return nil
  end
  local parent = node:parent()
  if not parent then
    return nil
  end
  local kind = parent:type()
  if not (kind:find("declaration", 1, true) or kind:find("definition", 1, true)) then
    return nil
  end
  for _, name in ipairs(parent:field("name")) do
    if name:id() == node:id() then
      return node
    end
  end
end

local function forget_old()
  local now = vim.uv.now()
  for key, entry in pairs(entries) do
    if now - entry.at > TTL then
      entries[key] = nil
    end
  end
  while #order > MAX do
    entries[table.remove(order, 1)] = nil
  end
end

--- Ask (once) for the usages of the declaration named at (row, col) of `buf`. Returns its entry, or nil when there
--- is no declaration name there or no server for it.
function M.request(buf, row, col)
  local name = M.declaration_name(buf, row, col)
  if not name then
    return nil
  end
  local clients = vim.lsp.get_clients({ bufnr = buf, method = METHOD })
  if #clients == 0 then
    return nil
  end
  forget_old()
  local srow, scol = name:range()
  local key = table.concat({ buf, api.nvim_buf_get_changedtick(buf), srow, scol }, ":")
  if entries[key] then
    return entries[key]
  end
  local entry =
    { key = key, at = vim.uv.now(), done = false, items = {}, waiters = {}, pending = #clients }
  entries[key], order[#order + 1] = entry, key
  local function finished()
    entry.pending = entry.pending - 1
    if entry.pending <= 0 and not entry.done then
      entry.done = true
      for _, fn in ipairs(entry.waiters) do
        fn(entry.items)
      end
      entry.waiters = {}
    end
  end
  local uri = vim.uri_from_bufnr(buf)
  for _, client in ipairs(clients) do
    local params = {
      textDocument = { uri = uri },
      position = {
        line = srow,
        character = vim.lsp.util.character_offset(buf, srow, scol, client.offset_encoding),
      },
      context = { includeDeclaration = false },
    }
    local sent = client:request(METHOD, params, function(err, result)
      if not err and result then
        result = vim.islist(result) and result or { result }
        vim.list_extend(
          entry.items,
          vim.lsp.util.locations_to_items(result, client.offset_encoding)
        )
      end
      finished()
    end, buf)
    if not sent then
      finished()
    end
  end
  return entry
end

--- Call `fn(items)` once the usages are in (now, when they already are).
function M.when_done(entry, fn)
  if entry.done then
    fn(entry.items)
  else
    table.insert(entry.waiters, fn)
  end
end

local function to_item(loc)
  return {
    text = loc.filename .. " " .. loc.text,
    file = loc.filename,
    pos = { loc.lnum, loc.col - 1 },
    end_pos = loc.end_lnum and loc.end_col and { loc.end_lnum, loc.end_col - 1 } or nil,
    line = loc.text,
  }
end

--- The usages of the declaration under the cursor in the references list (Snacks' lsp_references look).
function M.show()
  local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(win)
  local entry = M.request(buf, cursor[1] - 1, cursor[2])
  if not entry then
    return Snacks.picker.lsp_references({ include_declaration = false })
  end
  local function jump(item)
    vim.cmd("normal! m'")
    if vim.fs.normalize(api.nvim_buf_get_name(0)) ~= vim.fs.normalize(item.filename) then
      vim.cmd.edit(vim.fn.fnameescape(item.filename))
    end
    pcall(api.nvim_win_set_cursor, 0, { item.lnum, item.col - 1 })
    vim.cmd("normal! zz")
  end
  if entry.done and #entry.items == 1 then
    return jump(entry.items[1])
  end
  local picker
  -- the list was shown while loading: Snacks opens a single result by itself only when it was not, so do it here
  M.when_done(entry, function(items)
    if #items == 1 then
      vim.schedule(function()
        if picker and not picker.closed then
          picker:close()
          if api.nvim_win_is_valid(win) then
            api.nvim_set_current_win(win)
          end
          jump(items[1])
        end
      end)
    end
  end)
  picker = Snacks.picker.pick("lsp_references", {
    include_declaration = false,
    -- shown at once (a loading list) instead of after 5 s without results
    show_delay = entry.done and 0 or 120,
    finder = function(_, ctx)
      return function(cb)
        local items, waiting = nil, true
        M.when_done(entry, function(got)
          items = got
          if not waiting then
            ctx.async:resume()
          end
        end)
        waiting = false
        while not items do
          ctx.async:suspend()
        end
        for _, loc in ipairs(items) do
          cb(to_item(loc))
        end
      end
    end,
  })
end

--- What is kept (for tests).
function M.entries()
  return entries
end

function M.setup()
  local group = api.nvim_create_augroup("UsagesPrefetch", { clear = true })
  api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then
        return
      end
      local cursor = api.nvim_win_get_cursor(0)
      M.request(ev.buf, cursor[1] - 1, cursor[2])
    end,
  })
  -- a saved file can add or remove usages anywhere
  api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function()
      entries, order = {}, {}
    end,
  })
end

return M
