local ok, sqlite = pcall(require, "sqlite.db")
if not ok then
  error "Firefox depends on sqlite.lua (https://github.com/tami5/sqlite.lua)"
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local utils = require("telescope.utils")
local entry_display = require("telescope.pickers.entry_display")

local firefox = {}

-- Configuration values
local config = {}

-- Local database related variables
local dbfile, dbcopy
local history_sql_query = "SELECT b.title AS Title, b.url AS URL, DATETIME(a.visit_date/1000000,'unixepoch') AS DateAdded FROM moz_historyvisits AS a JOIN moz_places AS b ON b.id = a.place_id ORDER BY DateAdded DESC"
local bookmarks_sql_query = "SELECT c.title AS Parent, a.title AS Title, b.url AS URL, DATETIME(a.dateAdded/1000000,'unixepoch') AS DateAdded FROM moz_bookmarks AS a JOIN moz_places AS b ON a.fk = b.id, moz_bookmarks AS c WHERE a.parent = c.id"
local search_sql_query = "SELECT title AS Title, description AS Description, url AS URL, DATETIME(last_visit_date/1000000,'unixepoch') AS LastDate FROM moz_places ORDER BY LastDate DESC"

local function file_copy(src, dst)
  local fsrc, serr = io.open(src, 'rb')
  if serr then
    error(serr)
  end
  local data = fsrc:read('*a')
  fsrc:close()
  local fdst, derr = io.open(dst, 'w')
  if derr then
    error(derr)
  end
  fdst:write(data)
  fdst:close()
end


local function get_results(sql_query)
  local db = sqlite.new(dbcopy):open()
  local rows = db:eval(sql_query)
  return rows
end

local function make_history_line(v)
  return (v.DateAdded or "") .. " " .. (v.Title or "") .. " " .. (v.URL or "")
end

local function make_bookmarks_line(v)
  return (v.DateAdded or "") .. " " .. (v.Parent or "") .. " " .. (v.Title or "") .. " " .. (v.URL or "")
end

local function make_search_line(v)
  return (v.LastDate or "") .. " " .. (v.Title or "") .. " " .. (v.Description or "") .. " " .. (v.URL or "")
end

local function url_opener()
  return function(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    -- If multi-selection, use those values, otherwise choose the selected entry
    local selections = #picker:get_multi_selection() > 0 and picker:get_multi_selection() or { action_state.get_selected_entry() }
    actions.close(prompt_bufnr)
    for _, selection in ipairs(selections) do
      local _, ret, stderr = utils.get_os_command_output { config.url_open_command, selection.value }
      if ret ~= 0 then
        print(string.format('Error when opening %s: "%s"', selection.value, table.concat(stderr, "  ")))
      end
    end
  end
end

local function copy_to_register(prompt_bufnr)
  local picker = action_state.get_current_picker(prompt_bufnr)
  -- If multi-selection, use those values, otherwise choose the selected entry
  if #picker:get_multi_selection() > 0 then
    local selections = picker:get_multi_selection()
    actions.close(prompt_bufnr)
    local data = ""
    for _, selection in ipairs(selections) do
      data = data .. selection.value .. '\n'
    end
    vim.fn.setreg(vim.v.register, data)
  else
    actions.close(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    vim.fn.setreg(vim.v.register, selection.value)
  end
end

-- Initialize the extension
firefox.init = function(user_config)
  config = user_config

  dbfile = vim.fn.globpath(config.firefox_profile_dir, config.firefox_profile_glob .. '/places.sqlite')
  if not dbfile then
    error "Cannot find Firefox database"
  end

  -- Make a temporary copy of the database in case Firefox is running and has
  -- locked the database
  dbcopy = vim.fn.tempname()
  file_copy(dbfile, dbcopy)
end

local history_displayer = entry_display.create {
  separator = " ",
  items = {
    { width = 20 },
    { width = 70 },
    { remaining = true },
  },
}

local make_history_display = function(entry)
  return history_displayer {
    { entry.DateAdded or "", "TelescopeFirefoxDate" },
    { entry.Title or "", "TelescopeFirefoxTitle" },
    { entry.URL or "", "TelescopeFirefoxUrl" }
  }
end

-- History command
firefox.history = function(opts)
  opts = opts or {}
  local results = get_results(history_sql_query)
  if not results or vim.tbl_isempty(results) then
      return
  end

  pickers.new(opts, {
    prompt_title = "History",
    finder = finders.new_table {
      results = results,
      entry_maker = function(entry)
        local name = make_history_line(entry)
        entry.value = entry.URL
        entry.ordinal = name
        entry.display = make_history_display
        return entry
      end
    },
    previewer = false,
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(url_opener())
      map('i', '<C-y>', function() copy_to_register(prompt_bufnr) end)
      return true
    end,
  }):find()
end

local bookmarks_displayer = entry_display.create {
  separator = " ",
  items = {
    { width = 11 },
    { width = 16 },
    { width = 70 },
    { remaining = true },
  },
}

local make_bookmarks_display = function(entry)
  return bookmarks_displayer {
    { entry.DateAdded or "", "TelescopeFirefoxDate" },
    { entry.Parent or "", "TelescopeFirefoxFolder" },
    { entry.Title or "", "TelescopeFirefoxTitle" },
    { entry.URL or "", "TelescopeFirefoxUrl" }
  }
end

-- Bookmarks command
firefox.bookmarks = function(opts)
  opts = opts or {}
  local results = get_results(bookmarks_sql_query)
  if not results or vim.tbl_isempty(results) then
      return
  end

  pickers.new(opts, {
    prompt_title = "Bookmarks",
    finder = finders.new_table {
      results = results,
      entry_maker = function(entry)
        local name = make_bookmarks_line(entry)
        entry.value = entry.URL
        entry.ordinal = name
        entry.display = make_bookmarks_display
        return entry
      end
    },
    previewer = false,
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(url_opener())
      map('i', '<C-y>', function() copy_to_register(prompt_bufnr) end)
      return true
    end,
  }):find()
end

local search_displayer = entry_display.create {
  separator = " ",
  items = {
    { width = 11 },
    { width = 120 },
    { remaining = true },
  },
}

local make_search_display = function(entry)
  return search_displayer {
    { entry.LastDate or "", "TelescopeFirefoxDate" },
    { (entry.Title or "") .. " " .. (entry.Description or ""), "TelescopeFirefoxTitle" },
    { entry.URL or "", "TelescopeFirefoxUrl" }
  }
end

-- Search command: Does the bookmarks and history queries and joins the results,
-- showing them as a History query.
firefox.search = function(opts)
  opts = opts or {}
  local results = get_results(search_sql_query)
  if not results or vim.tbl_isempty(results) then
      return
  end

  pickers.new(opts, {
    prompt_title = "Search",
    finder = finders.new_table {
      results = results,
      entry_maker = function(entry)
        local name = make_search_line(entry)
        entry.value = entry.URL
        entry.ordinal = name
        entry.display = make_search_display
        return entry
      end
    },
    previewer = false,
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(url_opener())
      map('i', '<C-y>', function() copy_to_register(prompt_bufnr) end)
      return true
    end,
  }):find()
end

return firefox
