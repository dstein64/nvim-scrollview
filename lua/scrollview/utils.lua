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

return M
