local M = {}

function M.setup()
  local Picker = require("snacks.picker.core.picker")
  local widths = {} -- tab -> source -> manually chosen sidebar width
  local function remember(picker)
    if not picker.opts.source then
      return
    end
    local layout = picker.layout
    local root = layout and not layout.closed and layout.root
    if not (layout and layout.split and root and root:win_valid()) then
      return
    end
    local position = layout.opts.layout.position
    if position ~= "left" and position ~= "right" then
      return
    end
    local tab = vim.api.nvim_win_get_tabpage(root.win)
    local now = {
      win = root.win,
      width = vim.api.nvim_win_get_width(root.win),
      columns = vim.o.columns,
    }
    local before = picker._pane_dimensions
    if
      not before
      or (before.columns == now.columns and before.win == now.win and before.width ~= now.width)
    then
      widths[tab] = widths[tab] or {}
      widths[tab][picker.opts.source] = now.width
    end
    picker._pane_dimensions = now
  end
  local function sized_layout(picker, layout)
    local tab = vim.api.nvim_get_current_tabpage()
    local width = widths[tab] and widths[tab][picker.opts.source]
    if not width then
      return layout
    end
    local config = require("snacks.picker.config")
    layout = layout or config.layout(picker.opts)
    layout = type(layout) == "string" and config.layout(layout) or layout
    local position = layout.layout and layout.layout.position
    if position ~= "left" and position ~= "right" then
      return layout
    end
    layout = vim.deepcopy(layout)
    layout.layout.width = width
    -- Explicit dragging is allowed to make a pane narrower than its default.
    layout.layout.min_width = math.min(layout.layout.min_width or width, width)
    return layout
  end
  local init_layout = Picker.init_layout
  Picker.init_layout = function(self, layout)
    return init_layout(self, sized_layout(self, layout))
  end
  local set_layout = Picker.set_layout
  -- Snacks schedules set_layout on every VimResized, including for pickers in
  -- inactive tabs. Rebuilding their split layout there moves it into the current
  -- tab. Check ownership when the scheduled call runs, not when it is queued.
  Picker.set_layout = function(self, layout)
    if self.closed then
      return
    end
    if not self:on_current_tab() then
      return
    end
    remember(self)
    return set_layout(self, sized_layout(self, layout))
  end
  local group = vim.api.nvim_create_augroup("PickerResizeTab", { clear = true })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for _, picker in ipairs(Picker.get({ tab = false })) do
        remember(picker)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      vim.schedule(function()
        for _, picker in ipairs(Picker.get()) do
          picker:set_layout()
        end
      end)
    end,
  })
end

return M
