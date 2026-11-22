-- Core configuration loader
require("core.options")
require("core.cursor-visibility").setup()
require("core.keymaps")
require("core.gui-keymaps")
require("core.non-english-keyboard").setup()
require("core.autocmds")
require("core.resume-file").setup()
require("core.guess-indent").setup()
require("core.external-changes")
require("core.sidebars")
require("core.herdr-ref")
require("core.snacks-input-guard")
require("core.cmdline-file")
require("core.rtl").setup() -- right-to-left text drawn in visual order (GNU FriBidi), display only
require("core.file-cache").setup()
require("core.selection-highlight").setup()
require("core.json-modal")
require("core.http-files")
require("core.http-highlight").setup()
require("modules.http_requests")
require("core.modal-backdrop").setup()
require("core.diff-inlay-hints").setup() -- quiet gray hints in the Git diff views
require("core.find-bar").setup()
require("modules.phpunit.gutter").setup()
require("core.lazy")
require("core.code-action-order").setup()
require("core.project-lsp").setup()
require("core.git-jumps").setup()
require("core.picker-resize").setup()
require("core.wheel-cursor").setup()
require("core.diagnostic-card").setup()
-- Track file visits before the first picker opens; reuse Snacks' persistent history for all searches.
vim.api.nvim_create_autocmd("VimEnter", {
  group = vim.api.nvim_create_augroup("SearchFileUsage", { clear = true }),
  once = true,
  callback = function()
    require("snacks.picker.core.frecency").new()
  end,
})
-- a file picked while in the git pane opens in an editor tab (needs snacks, loaded by lazy)
pcall(function()
  require("core.leave-codediff").setup()
end)
