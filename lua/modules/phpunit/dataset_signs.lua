-- A test with a data provider gets its own icon (like VS Code), in the gutter and in the pane.
--
-- neotest's status consumer puts one sign per test (group "neotest-status"). After it has drawn, this consumer swaps
-- the sign of every test that ran with data sets for a "list" icon of the same status, in the same group, so a
-- click on it still runs the test (gutter.lua) and neotest's next redraw replaces it, to be swapped again.
local M = {}

--- The icon of a test that has data sets, per status (the colour says the status, the shape says "several").
M.ICON = { test = "󰙅", passed = "󰙅", failed = "󰙅", skipped = "󰙅", running = "󰙅" }

local GROUP = "neotest-status"
local HL = {
  test = "NeotestTest", passed = "NeotestPassed", failed = "NeotestFailed", skipped = "NeotestSkipped", running = "NeotestRunning",
}

local defined = false
local function define()
  if defined then
    return
  end
  defined = true
  for status, hl in pairs(HL) do
    vim.fn.sign_define("phpunit_sets_" .. status, { text = M.ICON[status], texthl = hl })
  end
end

--- Swap the signs of `lines` (1-based, the tests with data sets) in `buf`.
function M.swap(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  define()
  local placed = vim.fn.sign_getplaced(buf, { group = GROUP })[1]
  for _, sign in ipairs(placed and placed.signs or {}) do
    local status = sign.name:match("^neotest_(%a+)$")
    if status and lines[sign.lnum] and HL[status] then
      vim.fn.sign_unplace(GROUP, { buffer = buf, id = sign.id })
      vim.fn.sign_place(0, GROUP, "phpunit_sets_" .. status, buf, { lnum = sign.lnum, priority = 1000 })
    end
  end
end

--- Called by neotest (a consumer) with its client.
function M.attach(client)
  local nio = require("nio")

  local draw
  function draw(adapter_id, files)
    -- neotest's own consumer draws on the same events: wait for it
    -- (and sometimes later than expected: swap again a little later, it changes nothing once swapped)
    for _, wait in ipairs({ 60, 200, 600 }) do
      nio.sleep(wait)
      M.draw_once(client, adapter_id, files)
    end
  end

  function M.draw_once(client, adapter_id, files)
    local results = client:get_results(adapter_id)
    for file in pairs(files) do
      local tree = client:get_position(file, { adapter = adapter_id })
      local buf = nio.fn.bufnr(file)
      if tree and buf ~= -1 then
        local lines = {}
        for _, node in tree:iter_nodes() do
          local data = node:data()
          local result = data.type == "test" and results[data.id]
          if result and result.datasets and #result.datasets > 0 and data.range then
            lines[data.range[1] + 1] = true
          end
        end
        nio.scheduler()
        M.swap(buf, lines)
      end
    end
  end

  local function of_ids(adapter_id, ids)
    local files = {}
    for _, id in ipairs(ids) do
      local node = client:get_position(id, { adapter = adapter_id })
      if node and node:data().type ~= "dir" then
        files[node:data().path] = true
      end
    end
    return files
  end

  client.listeners.results = function(adapter_id, results)
    draw(adapter_id, of_ids(adapter_id, vim.tbl_keys(results)))
  end
  client.listeners.run = function(adapter_id, _, ids)
    draw(adapter_id, of_ids(adapter_id, ids))
  end
  client.listeners.discover_positions = function(adapter_id, tree)
    if tree:data().type == "file" then
      draw(adapter_id, { [tree:data().id] = true })
    end
  end
  client.listeners.test_file_focused = function(adapter_id, file)
    draw(adapter_id, { [file] = true })
  end
end

return M
