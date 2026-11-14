local M = {}

function M.setup()
  local Picker = require("snacks.picker.core.picker")
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
    return set_layout(self, layout)
  end
  vim.api.nvim_create_autocmd("TabEnter", {
    group = vim.api.nvim_create_augroup("PickerResizeTab", { clear = true }),
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
