-- A prompt (vim.ui.input / Snacks.input) keeps every character typed right before Enter. Snacks' Enter was an
-- expression mapping that confirmed while its expression was evaluated; Neovim evaluates it already when it peeks at
-- the next key during the insertion of the character before (typed fast, or a busy machine): the last character was
-- lost ("body<CR>" gave "bod").
local lib = require("lib")
local h = require("support")

local function prompt(screen, default)
  screen:exec([[
    _G.got = nil
    vim.ui.input({ prompt = "Name: ", default = ... }, function(v) _G.got = v or false end)
  ]], { default })
  h.wait(screen, function()
    return screen:exec("return vim.bo.filetype == 'snacks_input' and vim.fn.mode() == 'i'")
  end, "the prompt did not open")
  h.wait(screen, function() -- typing replaces a default once its selection is shown
    return default == "" or screen:exec("return vim.b.input_default_selection == true")
  end, "the default is not selected")
end

lib.test("input: keys typed together with Enter all reach the answer", function()
  local screen = h.nvim(h.tmpdir())
  -- Neovim gathers characters typed fast (peeking at the next key) only when no InsertCharPre autocommand exists:
  -- blink.cmp adds one when its setup is done, which takes longer on a busy machine. As before that:
  screen:exec("vim.api.nvim_clear_autocmds({ event = 'InsertCharPre' })")
  for _, case in ipairs({ { "", "body" }, { "content", "body" }, { "", "a" }, { "content", "contentType", "<End>Type" } }) do
    prompt(screen, case[1])
    -- the editor is busy a moment while the keys come in (typed faster than it runs): they all wait together
    screen:exec("vim.schedule(function() local t = vim.uv.hrtime() while vim.uv.hrtime() - t < 3e8 do end end)")
    screen:input((case[3] or case[2]) .. "<CR>")
    h.wait(screen, function()
      return screen:exec("return _G.got") ~= nil
    end, "the prompt was not confirmed")
    lib.eq(case[2], screen:exec("return _G.got"), "typed " .. (case[3] or case[2]) .. "<CR> with default '" .. case[1] .. "'")
  end
  screen:close()
end)
