local api = vim.api
local fn = vim.fn
local scrollview = require('scrollview')

local M = {}

function M.init()
  if api.nvim_create_autocmd == nil then
    return
  end

  scrollview.register_sign_spec('scrollview_textwidth', {
    priority = 20,
    symbol = fn.nr2char(0xbb),
    highlight = 'MoreMsg', -- TODO
  })

  api.nvim_create_autocmd('User', {
    pattern = 'ScrollViewRefresh',
    callback = scrollview.signs_autocmd_callback(function(args)
      -- Track visited buffers, to prevent duplicate computation when multiple
      -- windows are showing the same buffer.
      local visited = {}
      for _, winid in ipairs(scrollview.get_ordinary_windows()) do
        local bufnr = api.nvim_win_get_buf(winid)
        local textwidth = api.nvim_buf_get_option(bufnr, 'textwidth')
        if not visited[bufnr] then
          local winnr = api.nvim_win_get_number(winid)
          local bufvars = vim.b[bufnr]
          local lines = {}
          local cache_hit = false
          local seq_cur = fn.undotree().seq_cur
          if bufvars.scrollview_textwidth_option_cached == textwidth then
            local cache_seq_cur = bufvars.scrollview_textwidth_seq_cur_cached
            cache_hit = cache_seq_cur == seq_cur
          end
          if cache_hit then
            lines = bufvars.scrollview_textwidth_cached
          else
            local line_count = api.nvim_buf_line_count(0)
            -- Longline signs are not shown when the number of buffer
            -- lines exceeds the limit, to prevent a slowdown.
            -- TODO: set for real
            -- local line_count_limit = scrollview.get_variable(
            --   'scrollview_textwidth_buffer_lines_limit', winnr)
            local line_count_limit = -1  -- TODO: delete
            local within_limit = line_count_limit == -1
                or line_count <= line_count_limit
            if textwidth > 0 and within_limit then
              api.nvim_win_call(winid, function()
                for line = 1, line_count do
                  local line_length = fn.strchars(fn.getline(line), 1)
                  if line_length > textwidth then
                    table.insert(lines, line)
                  end
                end
              end)
            end
            bufvars.scrollview_textwidth_option_cached = textwidth
            bufvars.scrollview_textwidth_seq_cur_cached = seq_cur
            bufvars.scrollview_textwidth_cached = lines
          end
          bufvars.scrollview_textwidth = lines
          visited[bufnr] = true
        end
      end
    end)
  })

  api.nvim_create_autocmd('OptionSet', {
    callback = scrollview.signs_autocmd_callback(function(args)
      local amatch = fn.expand('<amatch>')
      if amatch == 'textwidth' then
        scrollview.refresh()
      end
    end)
  })
end

return M
