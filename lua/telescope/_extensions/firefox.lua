local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
  error('This plugin requires nvim-telescope/telescope.nvim')
end

-- Set default values for highlighting groups
vim.cmd("highlight default link TelescopeFirefoxDate Number")
vim.cmd("highlight default link TelescopeFirefoxFolder Keyword")
vim.cmd("highlight default link TelescopeFirefoxTitle Function")
vim.cmd("highlight default link TelescopeFirefoxUrl Comment")

local config = {}

local function set_config(opt_name, value, default)
  config[opt_name] = value == nil and default or value
end

return telescope.register_extension {
  setup = function(ext_config)
    set_config("url_open_command", ext_config.url_open_command, "xdg-open")
    set_config("firefox_profile_dir", ext_config.firefox_profile_dir, "~/.mozilla/firefox")
    set_config("firefox_profile_glob", ext_config.firefox_profile_glob, "*.default*")
    require("telescope._extensions.firefox.firefox").init(config)
    end,
  exports = {
    search = require("telescope._extensions.firefox.firefox").search,
    bookmarks = require("telescope._extensions.firefox.firefox").bookmarks,
    history = require("telescope._extensions.firefox.firefox").history
  }
}

