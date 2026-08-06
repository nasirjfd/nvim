return {
  {
    "kndndrj/nvim-dbee",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    build = function()
      -- Install tries to automatically detect the install method.
      -- if it fails, try calling it with one of these parameters:
      --    "curl", "wget", "bitsadmin", "go"
      require("dbee").install()
    end,
    config = function()
      require("dbee").setup({
        sources = {
          require("dbee.sources").MemorySource:new({
            {
              name = "Production",
              type = "mysql",
              url = "mysql://nasir.jafarzadeh:2pkdyGGavhqn@172.30.5.41:13306",
            },
          }),
        },
      })
    end,
  },
}
