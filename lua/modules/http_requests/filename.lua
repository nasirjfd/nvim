local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("HttpFilenameSuffix")

function M.normalize(name)
  name = vim.trim(name or "")
  -- Accept a pasted complete filename without duplicating the fixed suffix.
  while name:lower():sub(-5) == ".http" do
    name = name:sub(1, -6)
  end
  if name == "" then
    return nil
  end
  return name .. ".http"
end

function M.input(prompt, on_confirm)
  local input = vim.ui.input({
    prompt = prompt,
    win = { footer = " .http · fixed extension ", footer_pos = "right" },
  }, function(name)
    local filename = M.normalize(name)
    if filename then
      on_confirm(filename)
    end
  end)
  -- The suffix is display-only, never editable text or part of the input value.
  -- Keep vim.ui.input compatible with other providers (and callers that stub it).
  if type(input) ~= "table" or not input.buf or not api.nvim_buf_is_valid(input.buf) then
    return
  end
  local function suffix()
    if not api.nvim_buf_is_valid(input.buf) then
      return
    end
    local text = api.nvim_buf_get_lines(input.buf, 0, 1, false)[1] or ""
    api.nvim_buf_set_extmark(input.buf, ns, 0, #text, {
      id = 1,
      virt_text = { { ".http", "Comment" } },
      virt_text_pos = "inline",
      right_gravity = true,
    })
  end
  suffix()
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = input.buf,
    callback = suffix,
  })
end

return M
