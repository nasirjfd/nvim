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
