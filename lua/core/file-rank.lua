-- JetBrains-like ranking for the file pickers (snacks matcher `on_match`), on top of snacks' fuzzy
-- score (~16 per matched letter):
--   1. the search is made of the starts of words of the file name, in order: `pprecord` =
--      Parcel Projection Record, `ppr` too, `scl` = ScannableCodeLookup… (words may be skipped,
--      fewer skipped ranks higher)
--   2. the search is a piece of the file name: `post` in PostPaymentAPIPayload.php
-- Case never matters. Files that only match through their folders or by scattered letters come after.
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

function M.on_match(matcher, item)
  local q = (matcher.pattern or ""):lower():gsub("%s+", "")
  if #q < 2 or not item.file or q:find("[^%w]") then
    return
  end
  local name = vim.fs.basename(item.file)
  local lower = name:lower()
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
      item.score = item.score + PIECE_BONUS + (at == 1 and 100 or 0)
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
    -- fewer skipped words first: scl → ScannableCodeLookup… before Shipment…Cause…Claimed…
    item.score = item.score + WORD_BONUS - math.min(skips, 10) * 40
  end
end

return M
