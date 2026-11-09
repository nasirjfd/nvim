-- Hiding Kulala's response window safely.
--
-- Kulala hides it by deleting its buffer, which closes the window as a side effect. After an LSP
-- hover (gh) Neovim watches every closing window and reads that window's variables; a window closed
-- through a buffer delete is already gone by then, and Neovim raises "Invalid window id". Closing
-- the window first, while it is still valid, and deleting the buffer after avoids that.
local M = {}

function M.hide_response()
  local ok, ui = pcall(require, "kulala.ui")
  if not ok then
    return false
  end
  local buf = ui.get_kulala_buffer()
  if not buf then
    return false
  end
  local shown = false
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    shown = true
    if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1 then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  pcall(ui.close_kulala_buffer)
  return shown
end

-- F in the response window filters the response. Kulala's own filter is jq, for JSON; an HTML
-- response is filtered with a CSS selector instead (htmlq), showing only the matching elements below
-- the request summary, one match per line. Ending the selector with ::text shows only the text of
-- the matches (".price::text"). An empty selector shows the whole response again.
local last_selector = ""

local function is_html(response)
  local headers = type(response.headers) == "string" and response.headers or ""
  if headers:lower():find("content%-type:%s*[^\n]*html") then
    return true
  end
  local body = response.body_raw ~= "" and response.body_raw or response.body
  return type(body) == "string" and body:match("^%s*<") ~= nil and not body:match("^%s*<%?xml")
end

function M.filter()
  local ui = require("kulala.ui")
  local response = ui.get_current_response()
  if not is_html(response) then
    return ui.toggle_filter()
  end
  if vim.fn.executable("htmlq") == 0 then
    vim.notify("htmlq is not installed (brew install htmlq)", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "CSS selector (empty shows everything): ", default = last_selector }, function(selector)
    if selector == nil then
      return
    end
    selector = vim.trim(selector)
    last_selector = selector
    if selector == "" then
      return ui.show_body()
    end
    local body = response.body_raw ~= "" and response.body_raw or response.body
    local css, text_only = selector:gsub("%s*::text$", "")
    local cmd = text_only > 0 and { "htmlq", "--text", css } or { "htmlq", css }
    vim.system(cmd, { stdin = body, text = true }, vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        vim.notify("htmlq: " .. vim.trim(result.stderr ~= "" and result.stderr or "invalid selector"), vim.log.levels.ERROR)
        return
      end
      local buf = ui.get_kulala_buffer()
      if not buf then
        return
      end
      ui.show_body()
      local out = vim.tbl_filter(function(line)
        return vim.trim(line) ~= ""
      end, vim.split(result.stdout, "\n", { plain = true }))
      if #out == 0 then
        out = { "" }
      end
      if #out == 1 and out[1] == "" then
        out = { "(nothing matches " .. selector .. ")" }
      end
      -- the summary (request, URL, buffer) takes the first lines and a blank one; the body follows
      local first = 0
      for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 8, false)) do
        if line == "" then
          first = i
          break
        end
      end
      -- Kulala writes this buffer again on every view switch, so it is left as editable as it was
      local modifiable = vim.bo[buf].modifiable
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, first, -1, false, vim.list_extend({ "CSS Filter: " .. selector, "" }, out))
      vim.bo[buf].modifiable = modifiable
      vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("kulala_css_filter"), first, 0, { end_col = 11, hl_group = "Question" })
    end))
  end)
end

return M
