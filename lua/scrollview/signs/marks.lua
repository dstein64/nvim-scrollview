local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local concat = utils.concat
local to_bool = utils.to_bool

local M = {}

-- WARN: Prior to Neovim 0.10, the outcome of :delmarks does not persist across
-- Neovim sessions (Neovim #4288, #4925, #24963). Workaround: run :wshada!
-- after deleting marks (however, this could delete information, like the
-- changelist for files not edited in the current session).

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'marks'
  scrollview.register_sign_group(group)
  local names = {}  -- maps character to registration name
  for _, char in ipairs(vim.g.scrollview_marks_characters) do
    local registration = scrollview.register_sign_spec({
      group = group,
      highlight = 'ScrollViewMarks',
      priority = vim.g.scrollview_marks_priority,
      symbol = char,
      variant = char,
    })
    names[char] = registration.name
  end
  if vim.tbl_isempty(names) then return end
  scrollview.set_sign_group_state(group, enable)

  -- Refresh scrollbars after adding marks.
  for _, char in ipairs(vim.g.scrollview_marks_characters) do
    local seq = 'm' .. char
    scrollview.register_key_sequence_callback(seq, 'nv', scrollview.refresh)
  end

  scrollview.set_sign_group_callback(group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      local marks = {}  -- a mapping of character to line for buffer marks
      local items = concat(
        fn.getmarklist(bufnr),
        fn.getmarklist()
      )
      for _, item in ipairs(items) do
        if item.pos ~= nil
            and item.mark ~= nil
            and fn.strchars(item.mark, 1) == 2 then
          local char = fn.strcharpart(item.mark, 1, 1)
          -- Marks are (1, 0)-indexed (so we only have to check the first
          -- value for 0). Using nvim_buf_get_mark is a more reliable way to
          -- check for global marks versus the existing approach (see commit
          -- 53c14b5 and its WARN comments for details).
          local should_show = api.nvim_buf_get_mark(bufnr, char)[1] ~= 0
          if should_show then
            marks[char] = item.pos[2]
          end
        end
      end
      for _, char in ipairs(vim.g.scrollview_marks_characters) do
        local value = nil
        if marks[char] ~= nil then
          value = {marks[char]}
        end
        local name = names[char]
        -- luacheck: ignore 122 (setting read-only field b.?.? of global vim)
        vim.b[bufnr][name] = value
      end
    end
  end)

  api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      if not scrollview.is_sign_group_active(group) then return end
      if to_bool(vim.v.event.abort) then
        return
      end
      if fn.expand('<afile>') ~= ':' then
        return
      end
      -- Refresh scrollview after the following commands, which could change the marks.
      --   :[range]ma[rk] {a-zA-Z'}
      --   :[range]k{a-zA-Z'}
      --   :delm[arks] {marks}
      --   :kee[pmarks] {command}
      -- WARN: [range] is not handled.
      -- WARN: Only text at the beginning of the command is considered.
      -- WARN: CmdlineLeave is not executed for command mappings (<cmd>).
      -- WARN: CmdlineLeave is not executed for commands executed from Lua
      -- (e.g., vim.cmd('help')).
      local cmdline = fn.getcmdline()
      if vim.startswith(cmdline, 'ma')
          or vim.startswith(cmdline, 'k')
          or vim.startswith(cmdline, 'delm')
          or vim.startswith(cmdline, 'kee') then
        scrollview.refresh()
      end
    end
  })
end

return M
