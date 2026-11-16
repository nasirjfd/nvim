-- Filename-first fuzzy matching for ordinary file queries. Avoid repeatedly scoring
-- every possible match through long vendor paths; those are only fallback matches.
local M = {}

-- A forward/backward pass finds a compact alignment without rescoring every
-- occurrence of the first letter (Snacks' exhaustive fuzzy scorer is quadratic).
local function filename_score(matcher, text, original, chars)
  local first, last = 1, nil
  for _, char in ipairs(chars) do
    last = text:find(char, (last or 0) + 1, true)
    if not last then
      return nil
    end
  end
  local at = last
  for i = #chars, 1, -1 do
    local byte = chars[i]:byte()
    while text:byte(at) ~= byte do
      at = at - 1
    end
    first = at
    at = at - 1
  end
  matcher.score:init(original, first)
  at = first
  for i = 2, #chars do
    at = text:find(chars[i], at + 1, true)
    matcher.score:update(at)
  end
  return math.max(1, matcher.score.score)
end

function M.attach(matcher)
  local run = matcher.run
  matcher.run = function(self, picker)
    local items = picker.finder.items
    local fields =
      { "file_match_rank:desc", "file_usage:desc", "score:desc", "#text", "text", "idx" }
    if
      not self:empty()
      or self.opts.sort == false
      or picker.finder:running()
      or picker.opts.transform
      or not items[1]
      or not items[1]._cached_file
      or type(picker.opts.sort) ~= "table"
      or not vim.deep_equal(picker.opts.sort.fields, fields)
    then
      return run(self, picker)
    end
    -- The cache already has the complete file list. Build its opening order in
    -- one cheap pass instead of starting an async fuzzy match/heap for no query.
    -- These plain fd items cannot have seeded history, directories or score mods.
    self:abort()
    picker.list:clear()
    local history = self.frecency
    local cwd = vim.fs.normalize(picker.opts.cwd or vim.fn.getcwd()):gsub("/$", "")
    local ranked = {}
    for i, item in ipairs(items) do
      local path = cwd .. "/" .. item.file:gsub("^%./", "")
      local deadline = history and history.cache[path]
      local usage = deadline and history:to_score(deadline) or 0
      item.file_usage, item.frecency = usage, usage
      item._file_usage_source = history
      item.file_match_rank = 0
      item.score = 1000 + (1 - 1 / (1 + usage)) * 8 + (self.opts.cwd_bonus and 10 or 0)
      item.match_tick, item.match_topk = self.tick, nil
      ranked[i] = item
    end
    table.sort(ranked, function(a, b)
      if a.file_usage ~= b.file_usage then
        return a.file_usage > b.file_usage
      elseif #a.text ~= #b.text then
        return #a.text < #b.text
      elseif a.text ~= b.text then
        return a.text < b.text
      end
      return a.idx < b.idx
    end)
    self.sorting = true
    picker.list.items = ranked
    picker.list:unpause()
    picker:update({ force = true })
    self:on_done(picker)
  end
  local match = matcher.match
  matcher.match = function(self, item)
    local mod = self.one
    if not item.file then
      return match(self, item)
    end
    local text = item.text
    local cached = item._file_match
    if not cached or cached.text ~= text then
      local name = vim.fs.basename(item.file)
      cached = { text = text, lower = text:lower(), name = name, lower_name = name:lower() }
      item._file_match = cached
    end
    if not mod or not mod.fuzzy or mod.field or mod.inverse or mod.regex then
      return match(self, item)
    end
    local lower = mod.ignorecase and cached.lower or text
    -- Reject non-matches without invoking the fuzzy scorer at all. This matters
    -- most while extending a query: most paths fail after just a few finds.
    local first, last
    for i, char in ipairs(mod.chars) do
      last = lower:find(char, (last or 0) + 1, true)
      if not last then
        return 0
      end
      if i == 1 then
        first = last
      end
    end
    local name = mod.ignorecase and cached.lower_name or cached.name
    self.score.is_file = true
    local scores = self._filename_scores
    if not scores or scores.mod ~= mod then
      scores = { mod = mod, names = {} }
      self._filename_scores = scores
    end
    local score = scores.names[cached.name]
    if score == nil then
      score = filename_score(self, name, cached.name, mod.chars) or false
      scores.names[cached.name] = score
    end
    if score then
      return math.max(1, score)
    end
    -- Folder/scattered matches only need a fallback score. Filename matches keep
    -- boundary/consecutive bonuses, word ranking and opening-history priority.
    return math.max(1, #mod.chars * 16 - (last - first + 1 - #mod.chars))
  end
end

return M
