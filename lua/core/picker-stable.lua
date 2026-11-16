-- Keep the last complete file ranking on screen while Snacks matches the next query.
-- Matching still yields normally, so typing stays responsive on large projects.
local M = {}

function M.attach(picker)
  require("core.file-match").attach(picker.matcher)
  local list = picker.list
  local render = list.render
  list.render = function(self, ...)
    if picker.finder:running() or picker.matcher:running() then
      return
    end
    return render(self, ...)
  end

  -- Snacks' final forced update happens inside the matcher task, before it stops.
  -- on_done is scheduled after that task, including for an empty/no-match query.
  local on_done = picker.matcher.opts.on_done
  picker.matcher.opts.on_done = function(matcher)
    if on_done then
      on_done(matcher)
    end
    if not picker.closed and not picker.finder:running() and not matcher:running() then
      picker:update({ force = true })
    end
  end
end

return M
