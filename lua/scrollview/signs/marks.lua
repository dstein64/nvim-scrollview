local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')
local utils = require('scrollview.utils')
local concat = utils.concat
local to_bool = utils.to_bool

local M = {}

-- WARN: The outcome of :delmarks does not persist across Neovim sessions
-- (Neovim #4288, #4925). Workaround: run :wshada! after deleting marks.

function M.init()
  if api.nvim_create_autocmd == nil then
    return
  end

  local mark_chars = vim.g.scrollview_signs_marks_characters

  for _, char in ipairs(mark_chars) do
    scrollview.register_sign_spec('scrollview_signs_marks_' .. char, {
      priority = 50,
      symbol = char,
      highlight = 'ScrollViewSignsMarks',
    })
  end

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = scrollview.signs_autocmd_callback(function(args)
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
        local winfile = api.nvim_win_call(winid, function()
          return fn.expand('%:p')
        end)
        local bufnr = api.nvim_win_get_buf(winid)
        local marks = {}  -- a mapping of character to line for buffer marks
        local items = concat(
          fn.getmarklist(bufnr),
          fn.getmarklist()
        )
        for _, item in ipairs(items) do
          if item.pos ~= nil
              and item.mark ~= nil
              and fn.strcharlen(item.mark) == 2 then
            -- Global marks include a file.
            local file = item.file
            local should_show = false
            if file == nil then
              should_show = true  -- buffer mark
            else
              -- WARN: Marks won't show properly in cases where getmarklist()
              -- only includes a filename with no path, like for help files. We
              -- have no reliable way to know the corresponding buffer. Only
              -- proceed if we have a path.
              if file ~= fn.fnamemodify(file, ':t') then
                -- WARN: Marks wouldn't show properly for filenames that are
                -- empty (unsaved files), since getmarklist() doesn't return
                -- enough information to know which is the corresponding buffer
                -- (it just returns an empty string for the file, which could
                -- match multiple buffers).
                if file ~= '' then
                  should_show = fn.fnamemodify(file, ':p') == winfile
                end
              end
            end
            if should_show then
              local char = fn.strcharpart(item.mark, 1, 1)
              marks[char] = item.pos[2]
            end
          end
        end
        for _, char in ipairs(mark_chars) do
          local value = nil
          if marks[char] ~= nil then
            value = {marks[char]}
          end
          vim.b[bufnr]['scrollview_signs_marks_' .. char] = value
        end
      end
    end)
  })

  api.nvim_create_autocmd('CmdlineLeave', {
    callback = scrollview.signs_autocmd_callback(function(args)
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
      local cmdline = fn.getcmdline()
      if vim.startswith(cmdline, 'ma')
          or vim.startswith(cmdline, 'k')
          or vim.startswith(cmdline, 'delm')
          or vim.startswith(cmdline, 'kee') then
        scrollview.refresh()
      end
    end)
  })
end

return M
