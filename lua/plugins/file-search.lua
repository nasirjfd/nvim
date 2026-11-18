-- Within comparable filename matches, prefer files actually opened most
-- often/recently, not whichever path gets a slightly higher fuzzy score.
return {
  "folke/snacks.nvim",
  opts = function(_, opts)
    opts.picker = opts.picker or {}
    opts.picker.sources = opts.picker.sources or {}
    for _, source in ipairs({ "grep", "grep_word", "grep_buffers" }) do
      opts.picker.sources[source] = opts.picker.sources[source] or {}
      opts.picker.sources[source].format = function(item, picker)
        return require("core.grep-format").format(item, picker)
      end
    end
    opts.picker.sources.files = opts.picker.sources.files or {}
    opts.picker.sources.files.sort = {
      fields = { "file_match_rank:desc", "file_usage:desc", "score:desc", "#text", "text", "idx" },
    }
  end,
}
