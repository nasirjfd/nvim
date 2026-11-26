local lib = require("lib")
local h = require("support")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

lib.test("Ghostty forwards shifted Cmd J and K instead of pasting a screen-file path", function()
  local config = vim.fn.readfile(root .. "/ghostty/config")
  lib.ok(vim.tbl_contains(config, "keybind = super+shift+j=csi:106;10u"))
  lib.ok(vim.tbl_contains(config, "keybind = super+shift+k=csi:107;10u"))
end)

lib.test(
  "raw terminal Ctrl and Cmd Shift J/K duplicate HTTP selections without opening Find",
  function()
    local dir = h.tmpdir()
    local socket = dir .. "/nvim.sock"
    h.write(dir .. "/request.http", { "# one", "# two" })
    local screen = { stderr = "", flush = function() end }
    local job = vim.fn.jobstart({
      vim.v.progpath,
      "-u",
      root .. "/init.lua",
      "-i",
      "NONE",
      "--listen",
      socket,
    }, {
      pty = true,
      cwd = dir,
      width = 120,
      height = 35,
      env = { NVIM_CONFIG_TESTS = "1", TERM = "xterm-256color" },
      on_stdout = function(_, lines)
        screen.stderr = (screen.stderr .. table.concat(lines, "\n")):sub(-12000)
      end,
    })
    local rpc
    function screen:exec(code)
      return vim.rpcrequest(rpc, "nvim_exec_lua", code, {})
    end
    local ok, err = xpcall(function()
      h.wait(screen, function()
        return vim.uv.fs_stat(socket) ~= nil
      end, "terminal Neovim did not start")
      rpc = vim.fn.sockconnect("pipe", socket, { rpc = true })
      screen:exec("vim.cmd('edit request.http'); vim.opt.clipboard = ''")
      for _, key in ipairs({
        { "Ctrl+Shift+J", "\27[106;6u" },
        { "Ctrl+Shift+K", "\27[107;6u" },
        { "Cmd+Shift+J", "\27[106;10u" },
        { "Cmd+Shift+K", "\27[107;10u" },
      }) do
        screen:exec([[
        vim.cmd('normal! \27')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# one', '# two' })
        vim.cmd('normal! ggVj')
      ]])
        vim.fn.chansend(job, key[2])
        h.wait(screen, function()
          return screen:exec("return vim.api.nvim_buf_line_count(0) == 4")
        end, key[1] .. " did not duplicate the selection through the terminal")
        lib.eq(
          { "# one", "# two", "# one", "# two" },
          screen:exec("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
        )
        lib.ok(
          screen:exec([[
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'findbar' then return false end
        end
        return vim.fn.mode() == 'V'
      ]]),
          key[1] .. " opened Find or lost the visual selection"
        )
      end
    end, debug.traceback)
    if rpc then
      pcall(screen.exec, screen, "vim.cmd('qa!')")
      pcall(vim.fn.chanclose, rpc)
    end
    vim.fn.jobstop(job)
    lib.ok(ok, err)
  end
)
