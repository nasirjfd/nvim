local M = {}

function M.done(matcher, picker)
  matcher.opts.keep_parents = not matcher:empty()
  if picker.closed or matcher:empty() or matcher:running() then
    return
  end
  local files = {}
  for _, item in ipairs(picker.finder.items) do
    -- A file retained only as the ancestor of a request is not a filename hit.
    if item.kind == "file" and matcher:match(item) > 0 then
      files[item.file] = true
    end
  end
  local added = false
  for _, item in ipairs(picker.finder.items) do
    if item.kind == "request" and not item.in_pins and files[item.file] and item.score == 0 then
      item.score = 1
      item.match_tick = matcher.tick
      item.child_match_only = true
      picker.list:add(item, matcher.sorting)
      added = true
    end
  end
  if added then
    picker:update({ force = true })
  end
end

return M
