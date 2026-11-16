-- JetBrains-like ranking for the file pickers (snacks matcher `on_match`), on top of snacks' fuzzy
-- score (~16 per matched letter):
--   1. the search is made of the starts of words of the file name, in order: `pprecord` =
--      Parcel Projection Record, `ppr` too, `scl` = ScannableCodeLookup… (words may be skipped,
--      fewer skipped ranks higher)
--   2. the search is a piece of the file name: `post` in PostPaymentAPIPayload.php
-- Case never matters. Files that only match through their folders or by scattered letters come after.
-- Within the same match class, Files sorts opening history before skip/fuzzy-score differences.
local M = {}

local WORD_BONUS = 1000
local PIECE_BONUS = 500

-- Lower-case words of a file name: CamelCase, snake_case, kebab-case, dots, digits.
local function words(name)
  local list = {}
  name = name
    :gsub("(%l)(%u)", "%1 %2")
    :gsub("(%u)(%u%l)", "%1 %2")
    :gsub("(%a)(%d)", "%1 %2")
    :gsub("(%d)(%a)", "%1 %2")
  for w in name:gmatch("[%w]+") do
    list[#list + 1] = w:lower()
  end
  return list
end

-- How many words of the name are skipped when `q` is read as a run of word prefixes (each piece
-- starts a word, later pieces in later words), or nil when it can't be read that way.
local function skipped_words(q, list)
  local memo = {}
  local function go(qi, wi)
    if qi > #q then
      return 0
    end
    local key = qi * 1000 + wi
    if memo[key] ~= nil then
      return memo[key] or nil
    end
    local best
    for w = wi, #list do
      local word = list[w]
      local n = 0
      while n < #word and qi + n <= #q and q:sub(qi + n, qi + n) == word:sub(n + 1, n + 1) do
        n = n + 1
        -- n letters of this word, the rest from the following words
        local rest = go(qi + n, w + 1)
        if rest then
          local skips = rest + (w - wi)
          if not best or skips < best then
            best = skips
          end
        end
      end
    end
    memo[key] = best or false
    return best
  end
  return go(1, 1)
end

local cache = {} -- file name -> words

local function rank(q, name)
  local match_rank, bonus = 0, 0
  local lower = name:lower()
  if lower:sub(1, #q) == q then
    return { rank = 2, bonus = PIECE_BONUS + 100 + WORD_BONUS }
  end
  -- a piece that starts a word (not parcel*s* + *cl*aimed for scl)
  local from = 1
  while true do
    local at = lower:find(q, from, true)
    if not at then
      break
    end
    local prev, char = name:sub(at - 1, at - 1), name:sub(at, at)
    if
      at == 1
      or not prev:match("%w")
      or (prev:match("%l") and char:match("%u"))
      or (prev:match("%a") and char:match("%d"))
    then
      match_rank = 1
      bonus = PIECE_BONUS + (at == 1 and 100 or 0)
      break
    end
    from = at + 1
  end
  local list = cache[name]
  if not list then
    list = words(name)
    cache[name] = list
  end
  local skips = skipped_words(q, list)
  if skips then
    match_rank = 2
    -- fewer skipped words first: scl → ScannableCodeLookup… before Shipment…Cause…Claimed…
    bonus = bonus + WORD_BONUS - math.min(skips, 10) * 40
  end
  return { rank = match_rank, bonus = bonus }
end

function M.on_match(matcher, item)
  -- History is a snapshot for this picker. Resolve it once, not for every letter.
  if item._file_usage_source ~= matcher.frecency or item.file_usage == nil then
    item.file_usage = matcher.frecency and matcher.frecency:get(item, { seed = false }) or 0
    item._file_usage_source = matcher.frecency
  end
  item.file_match_rank = 0
  local state = matcher._file_rank
  if not state or state.pattern ~= matcher.pattern then
    local q = (matcher.pattern or ""):lower():gsub("%s+", "")
    state =
      { pattern = matcher.pattern, query = q, valid = #q >= 2 and not q:find("[^%w]"), names = {} }
    matcher._file_rank = state
  end
  if not state.valid or not item.file then
    return
  end
  local name = item._file_match and item._file_match.name or vim.fs.basename(item.file)
  local result = state.names[name]
  if not result then
    result = rank(state.query, name)
    state.names[name] = result
  end
  item.file_match_rank = result.rank
  item.score = item.score + result.bonus
end

return M
