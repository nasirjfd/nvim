-- Coding: Completion, treesitter, and dev tools
return {
  -- ════════════════════════════════════════════════════════════════════════════
  -- Completion (blink.cmp)
  -- ════════════════════════════════════════════════════════════════════════════
  {
    "saghen/blink.cmp",
    version = "*",
    config = function()
      require("blink.cmp").setup({
        snippets = { preset = "default" },
        signature = { enabled = true },
        appearance = {
          use_nvim_cmp_as_default = false,
          nerd_font_variant = "normal",
        },
        sources = {
          default = { "lazydev", "lsp", "path", "buffer", "snippets" },
          -- Lua scripts in .http files ({% -- lua … %}): Kulala's Lua API (core/kulala-lua.lua)
          per_filetype = { http = { "kulala_lua", "lsp", "path", "buffer", "snippets" } },
          providers = {
            kulala_lua = {
              name = "Kulala Lua",
              module = "core.kulala-lua",
              score_offset = 100,
            },
            -- Inside a Lua script block Kulala's server only adds noise (JavaScript-style snippets such
            -- as `response.json()`, header names), so the Lua source above answers alone there.
            lsp = {
              transform_items = function(_, items)
                local ok, kulala = pcall(require, "core.kulala-lua")
                if vim.bo.filetype == "http" and ok and kulala.in_lua_block(0, vim.api.nvim_win_get_cursor(0)[1]) then
                  return {}
                end
                return items
              end,
            },
            lazydev = {
              name = "LazyDev",
              module = "lazydev.integrations.blink",
              score_offset = 100,
            },
            cmdline = {
              min_keyword_length = 2,
            },
          },
        },
        keymap = {
          ["<C-f>"] = {},
          -- Ctrl+j / Ctrl+k move down / up in the menu; Enter accepts the selected item.
          -- With the menu closed they all fall back to their usual insert-mode behavior.
          ["<C-j>"] = { "select_next", "fallback" },
          ["<C-k>"] = { "select_prev", "fallback" },
          ["<CR>"] = { "accept", "fallback" },
          -- Tab accepts the selected item like Enter does; with the menu closed it jumps through snippets
          ["<Tab>"] = { "accept", "snippet_forward", "fallback" },
        },
        cmdline = {
          enabled = false,
          completion = { menu = { auto_show = true } },
          keymap = {
            ["<CR>"] = { "accept_and_enter", "fallback" },
          },
        },
        completion = {
          menu = {
            border = "rounded",
            scrolloff = 1,
            scrollbar = false,
            draw = {
              padding = 1,
              gap = 1,
              columns = {
                { "kind_icon" },
                { "label", "label_description", gap = 1 },
                { "kind" },
                { "source_name" },
              },
            },
          },
          documentation = {
            window = {
              border = "rounded",
              scrollbar = false,
              winhighlight = "Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,EndOfBuffer:BlinkCmpDoc",
            },
            auto_show = true,
            auto_show_delay_ms = 500,
          },
        },
      })
    end,
  },

  -- ════════════════════════════════════════════════════════════════════════════
  -- Treesitter
  -- ════════════════════════════════════════════════════════════════════════════
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      local parsers = {
        "bash", "c", "css", "go", "gomod", "gosum", "gowork",
        "html", "javascript", "json", "latex", "lua", "luadoc", "luap",
        "markdown", "markdown_inline", "php", "phpdoc", "proto", "python", "query",
        "regex", "rust", "scss", "svelte", "swift", "terraform",
        "tsx", "twig", "typescript", "vim", "vimdoc", "vue", "yaml", "zig",
      }
      require("nvim-treesitter").install(parsers)

      -- Enable treesitter-based highlighting and indentation per-buffer
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start)
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },

  -- ════════════════════════════════════════════════════════════════════════════
  -- Lua development
  -- ════════════════════════════════════════════════════════════════════════════
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },

  -- ════════════════════════════════════════════════════════════════════════════
  -- Autotags for HTML/JSX
  -- ════════════════════════════════════════════════════════════════════════════
  {
    "windwp/nvim-ts-autotag",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },

  -- ════════════════════════════════════════════════════════════════════════════
  -- Comments
  -- ════════════════════════════════════════════════════════════════════════════
  {
    "numToStr/Comment.nvim",
    opts = {},
    lazy = false,
  },
  { "joosepalviste/nvim-ts-context-commentstring", lazy = true },
}
