local M = {}

-- Returns the index of x in l if present, or the index for insertion
-- otherwise. Assumes that l is sorted.
function M.binary_search(l, x)
  local lo = 1
  local hi = #l
  while lo <= hi do
    local mid = math.floor((hi - lo) / 2 + lo)
    if l[mid] == x then
      if mid == 1 or l[mid - 1] ~= x then
        return mid
      end
      -- Keep searching for the leftmost match.
      hi = mid - 1
    elseif l[mid] < x then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return lo
end

-- Concatenate two array-like tables.
function M.concat(a, b)
  local result = {}
  for _, x in ipairs(a) do
    table.insert(result, x)
  end
  for _, x in ipairs(b) do
    table.insert(result, x)
  end
  return result
end

-- Create a shallow copy of a map-like table.
function M.copy(table)
  local result = {}
  for key, val in pairs(table) do
    result[key] = val
  end
  return result
end

-- Takes a list of lists. Each sublist is comprised of a highlight group name
-- and a corresponding string to echo.
function M.echo(echo_list)
  vim.cmd('redraw')
  for _, item in ipairs(echo_list) do
    local hlgroup, string = unpack(item)
    vim.g.scrollview_echo_string = string
    vim.cmd('echohl ' .. hlgroup .. ' | echon g:scrollview_echo_string')
    vim.g.scrollview_echo_string = vim.NIL
  end
  vim.cmd('echohl None')
end

-- For sorted list l with no duplicates, return the previous item before the
-- specified item (wraps around).
function M.preceding(l, item, count, wrapscan)
  assert(count >= 0)
  if count == 0 then
    -- This special-case handling is necessary. Without it, if item is not in
    -- the list, another item would be returned.
    return item
  end
  if vim.tbl_isempty(l) then
    return nil
  end
  local idx = M.binary_search(l, item) - count
  if idx < 1 then
    idx = wrapscan and (idx - 1) % #l + 1 or #l
  end
  return l[idx]
end

-- Return a new list with duplicate elements removed from a sorted array-like
-- table.
function M.remove_duplicates(l)
  local result = {}
  for _, x in ipairs(l) do
    if vim.tbl_isempty(result) or result[#result] ~= x then
      table.insert(result, x)
    end
  end
  return result
end

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
function M.round(x)
  return math.floor(x + 0.5)
end

-- A non-destructive sort function.
function M.sorted(l)
  local result = M.copy(l)
  table.sort(result)
  return result
end

-- For sorted list l with no duplicates, return the <count>th item after the
-- specified item.
function M.subsequent(l, item, count, wrapscan)
  assert(count >= 0)
  if count == 0 then
    -- This special-case handling is necessary. Without it, if item is not in
    -- the list, another item would be returned.
    return item
  end
  if vim.tbl_isempty(l) then
    return nil
  end
  local idx = M.binary_search(l, item)
  if idx <= #l and l[idx] == item then
    idx = idx + 1  -- use the next item
  end
  idx = idx + count - 1
  if idx > #l then
    idx = wrapscan and (idx - 1) % #l + 1 or #l
  end
  return l[idx]
end

-- Replace termcodes.
function M.t(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

-- Get value from a map-like table, using the specified default.
function M.tbl_get(table, key, default)
  local result = table[key]
  if result == nil then
    result = default
  end
  return result
end

-- Returns true for boolean true and any non-zero number, otherwise returns
-- false.
function M.to_bool(x)
  if type(x) == 'boolean' then
    return x
  elseif type(x) == 'number' then
    return x ~= 0
  end
  return false
end

return M
