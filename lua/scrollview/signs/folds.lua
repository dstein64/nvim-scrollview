local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init(enable)
  if api.nvim_create_autocmd == nil then
    return
  end

  local group = 'folds'
  scrollview.register_sign_group(group)
  local registration = scrollview.register_sign_spec({
    group = group,
    highlight = 'ScrollViewFolds',
    priority = vim.g.scrollview_folds_priority,
    show_in_folds = true,  -- so that cursor sign shows on fold start
    symbol = vim.g.scrollview_folds_symbol,
    type = 'w',
  })
  local name = registration.name
  scrollview.set_sign_group_state(group, enable)

  scrollview.set_sign_group_callback(group, function()
    for _, winid in ipairs(scrollview.get_sign_eligible_windows()) do
      local bufnr = api.nvim_win_get_buf(winid)
      local lines = scrollview.with_win_workspace(winid, function()
        local result = {}
        -- Linewise computation can be faster when there are many folds. See
        -- the comment in scrollview.lua::virtual_line_count for details. The
        -- same multiple, .006, is used here (it was not separately optimized
        -- for this scenario).
        local line_count = api.nvim_buf_line_count(bufnr)
        local threshold = math.floor(line_count * .006)
        if scrollview.fold_count_exceeds(1, line_count, threshold) then
          -- Linewise.
          local line = 1
          while line <= line_count do
            local foldclosedend = fn.foldclosedend(line)
            if foldclosedend ~= -1 then
              table.insert(result, line)
              line = foldclosedend
            end
            line = line + 1
          end
        else
          -- Foldwise.
          vim.cmd('keepjumps normal! gg')
          while true do
            local line = fn.line('.')
            if fn.foldclosed(line) ~= -1 then
              table.insert(result, line)
            end
            vim.cmd('keepjumps normal! zj')
            if line == fn.line('.') then
              break
            end
          end
        end
        return result
      end)
      -- luacheck: ignore 122 (setting read-only field w.?.? of global vim)
      vim.w[winid][name] = lines
    end
  end)
end

return M
