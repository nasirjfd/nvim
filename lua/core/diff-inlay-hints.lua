-- Inlay hints in the Git diff views (multi-repo-code-diff): gray text on the line's own diff colour, so the green /
-- red of an added / removed line runs through them instead of being cut by dark boxes. Elsewhere they keep the
-- colorscheme's look.
--
-- The diff colours a line with a range highlight (CodeDiffLineInsert / CodeDiffLineDelete), and Neovim never applies
-- range highlights to inline virtual text (not even with hl_mode "combine"): a hint without a background of its own
-- shows the editor's background. So, in a diff window, each hint is given the line's diff group with the gray hint
-- colour stacked on it. Neovim draws the hints in a decoration provider; this one is registered after it (its module
-- is loaded first) and restyles them in the window that is about to be drawn.
local M = {}

local api = vim.api
local GROUP = "CodeDiffInlayHint"

local function set_highlight()
  local hint = api.nvim_get_hl(0, { name = "LspInlayHint", link = false })
  local fg = hint.fg or api.nvim_get_hl(0, { name = "Comment", link = false }).fg
  api.nvim_set_hl(0, GROUP, { fg = fg, italic = hint.italic })
end

local function is_diff_window(win)
  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  local session = lifecycle and lifecycle.get_session(api.nvim_win_get_tabpage(win))
  return session ~= nil
    and (session.original_win == win or session.modified_win == win or session.result_win == win)
end

-- the diff group colouring row `row` of `buf` (an added / removed line), or nil
local function line_group(buf, row)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true, overlap = true })) do
    local group = mark[4].hl_group
    if type(group) == "string" and group:match("^CodeDiffLine") then
      return group
    end
  end
end

--- The hint chunks for a diff line: the line's group under the gray hint colour.
function M.restyle(chunks, group)
  local out, changed = {}, false
  for i, chunk in ipairs(chunks) do
    local want = group and { group, GROUP } or GROUP
    if not vim.deep_equal(chunk[2], want) then
      changed = true
    end
    out[i] = { chunk[1], want }
  end
  return out, changed
end

function M.setup()
  set_highlight()
  api.nvim_create_autocmd("ColorScheme", {
    group = api.nvim_create_augroup("DiffInlayHints", { clear = true }),
    callback = set_highlight,
  })
  require("vim.lsp.inlay_hint") -- its decoration provider first: this one runs after it
  local hints = api.nvim_create_namespace("nvim.lsp.inlayhint")
  api.nvim_set_decoration_provider(api.nvim_create_namespace("diff_inlay_hints"), {
    on_win = function(_, win, buf, topline, botline)
      if not is_diff_window(win) then
        return false
      end
      local marks = api.nvim_buf_get_extmarks(buf, hints, { topline, 0 }, { botline, -1 }, { details = true })
      for _, mark in ipairs(marks) do
        local id, row, col, details = mark[1], mark[2], mark[3], mark[4]
        if details.virt_text then
          local chunks, changed = M.restyle(details.virt_text, line_group(buf, row))
          if changed then
            pcall(api.nvim_buf_set_extmark, buf, hints, row, col, {
              id = id,
              virt_text = chunks,
              virt_text_pos = details.virt_text_pos,
              priority = details.priority,
            })
          end
        end
      end
      return false
    end,
  })
end

return M
