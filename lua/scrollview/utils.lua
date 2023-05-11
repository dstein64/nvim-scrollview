local M = {}

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

-- Round to the nearest integer.
-- WARN: .5 rounds to the right on the number line, including for negatives
-- (which would not result in rounding up in magnitude).
-- (e.g., round(3.5) == 3, round(-3.5) == -3 != -4)
function M.round(x)
  return math.floor(x + 0.5)
end

function M.reltime_to_microseconds(reltime)
  local reltimestr = vim.fn.reltimestr(reltime)
  return tonumber(table.concat(vim.split(reltimestr, '%.'), ''))
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

-- Create a shallow copy of a map-like table.
function M.copy(table)
  local result = {}
  for key, val in pairs(table) do
    result[key] = val
  end
  return result
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

-- A non-destructive sort function.
function M.sorted(l)
  local result = M.copy(l)
  table.sort(result)
  return result
end

-- Returns the index of x in l if present, or the index for insertion
-- otherwise.
function M.binary_search(l, x)
  local lo = 1
  local hi = #l
  while lo <= hi do
    local mid = math.floor((hi - lo) / 2 + lo)
    if l[mid] == x then
      return mid
    elseif l[mid] < x then
      lo = lo + 1
    else
      hi = hi - 1
    end
  end
  return lo
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

-- For sorted list l with no duplicates, return the next item after the
-- specified item (wraps around).
function M.subsequent(l, item)
  if vim.tbl_isempty(l) then
    return nil
  end
  local idx = M.binary_search(l, item)
  if idx <= #l and l[idx] == item then
    idx = idx + 1  -- use the next item
  end
  if idx > #l then
    idx = 1
  end
  return l[idx]
end

-- For sorted list l with no duplicates, return the previous item before the
-- specified item (wraps around).
function M.preceding(l, item)
  if vim.tbl_isempty(l) then
    return nil
  end
  local idx = M.binary_search(l, item) - 1
  if idx < 1 then
    idx = #l
  end
  return l[idx]
end

return M