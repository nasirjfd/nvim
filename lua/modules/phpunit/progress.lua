-- How far a run is, from 0 to the last test.
--
-- PHPUnit prints "  61 / 1122 (  5%)" as it goes (executions, data sets counted). The adapter's `stream`
-- (init.lua) feeds those numbers here; the runner announces which positions a batch of runs has before it starts, so
-- the total is known from the first moment (an estimate from what the tests did last time, replaced by PHPUnit's own
-- number when it prints it). The pane shows `state()` while it is not nil.
local M = {}

local batch ---@type { specs: table<string, table>, order: string[], auto: boolean }?

M.on_change = function() end -- the pane hooks in here

local function changed()
  pcall(M.on_change)
end

--- A batch of runs begins: `items` = { { key = position id, estimate = number of tests it will probably run } }.
function M.start(items)
  batch = { specs = {}, order = {}, auto = false }
  for _, item in ipairs(items) do
    batch.specs[item.key] = { estimate = item.estimate or 0, subs = {}, expect = 1, finished = 0 }
    batch.order[#batch.order + 1] = item.key
  end
  changed()
end

--- The batch is over (or was stopped).
function M.clear()
  batch = nil
  changed()
end

local function spec_of(key)
  if not batch then
    batch = { specs = {}, order = {}, auto = true }
  end
  if not batch.specs[key] then
    batch.specs[key] = { estimate = 0, subs = {}, expect = 1, finished = 0 }
    batch.order[#batch.order + 1] = key
  end
  return batch.specs[key]
end

--- The position `key` is run by `n` PHPUnit processes (one per project it covers).
function M.expect(key, n)
  spec_of(key).expect = n
end

--- PHPUnit process `sub` of position `key` says it has run `done` of `total`.
function M.update(key, sub, done, total)
  local spec = spec_of(key)
  spec.subs[sub] = spec.subs[sub] or {}
  spec.subs[sub].done, spec.subs[sub].total = done, total
  changed()
end

--- PHPUnit process `sub` of position `key` is over.
function M.finish(key, sub)
  if not batch or not batch.specs[key] then
    return
  end
  local spec = batch.specs[key]
  spec.subs[sub] = spec.subs[sub] or {}
  if not spec.subs[sub].over then
    spec.subs[sub].over = true
    spec.finished = spec.finished + 1
  end
  -- a run nobody announced is over when all of its specs are
  if batch.auto then
    for _, other in pairs(batch.specs) do
      if other.finished < other.expect then
        changed()
        return
      end
    end
    batch = nil
  end
  changed()
end

--- Where the batch is: { done, total, fraction } or nil when nothing runs.
function M.state()
  if not batch then
    return nil
  end
  local done, total = 0, 0
  for _, spec in pairs(batch.specs) do
    local known, sub_done, sub_total = 0, 0, 0
    for _, sub in pairs(spec.subs) do
      if sub.total then
        known = known + 1
        sub_total = sub_total + sub.total
        sub_done = sub_done + (sub.over and sub.total or (sub.done or 0))
      end
    end
    if known >= spec.expect and known > 0 then
      done, total = done + sub_done, total + sub_total
    else
      -- not heard from yet: what it probably has; what it did so far counts
      total = total + math.max(spec.estimate, sub_total)
      done = done + sub_done
    end
  end
  if total <= 0 then
    return { done = 0, total = 0, fraction = 0 }
  end
  return { done = math.min(done, total), total = total, fraction = math.min(done, total) / total }
end

return M
