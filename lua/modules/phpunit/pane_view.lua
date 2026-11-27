-- Tests-only viewport scrolling. Snacks normally keeps its selection on screen;
-- browsing with the wheel must not select a different test or change failure details.
local M = {}

function M.attach(picker)
  local list = picker.list
  local scroll, move, view = list.scroll, list.move, list.view
  local idx2row, cursorline = list.idx2row, list.update_cursorline
  local browsing = false
  function list:scroll(to, absolute, render)
    if to == 0 and not absolute then
      if not browsing then
        return scroll(self, to, absolute, render)
      end
      return
    end
    browsing = true
    self.target = nil
    local top = absolute and to or self.top + to
    self.top = math.max(1, math.min(top, math.max(1, self:count() - self:height() + 1)))
    self.dirty = true
    if render ~= false then
      self:render()
    end
  end
  function list:view(cursor, top, render)
    if not browsing then
      return view(self, cursor, top, render)
    end
    -- Background result refreshes restore a target view. Keep its offscreen
    -- selection instead of pulling the viewport back to it.
    self.cursor = math.max(1, math.min(cursor, self:count()))
    self.top = math.max(1, math.min(top or self.top, math.max(1, self:count() - self:height() + 1)))
    self.target = nil
    self.dirty = true
    if render ~= false then
      self:render()
    end
  end
  function list:move(to, absolute, render)
    if browsing and to == 0 and not absolute then
      return
    end
    browsing = false
    return move(self, to, absolute, render)
  end
  function list:idx2row(idx)
    local row = idx2row(self, idx)
    -- The physical cursor needs a valid screen row, but self.cursor keeps the
    -- actual selection even while it is outside the viewport.
    return browsing and math.max(1, math.min(row, self:height())) or row
  end
  function list:update_cursorline()
    cursorline(self)
    if browsing and self.win:win_valid() then
      vim.wo[self.win.win].cursorline = self.cursor >= self.top
        and self.cursor < self.top + self:height()
    end
  end
end

return M
