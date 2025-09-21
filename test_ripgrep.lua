-- Test ripgrep command directly
print("Testing ripgrep command...")

local cmd = {'rg', '--json', '--no-heading', '--with-filename', '--line-number', '--max-count', '5', 'function', '.'}

print("Command: " .. table.concat(cmd, ' '))

-- Test if ripgrep is available
if vim.fn.executable('rg') == 1 then
  print("✓ ripgrep is available")
  
  -- Try to run a simple command
  local handle = io.popen('rg --version')
  local result = handle:read('*a')
  handle:close()
  print("Ripgrep version: " .. result:sub(1, 50))
  
  -- Test the actual command structure
  local test_handle = io.popen('rg --json --no-heading --with-filename --line-number --max-count 5 "function" . 2>&1')
  local test_result = test_handle:read('*a')
  test_handle:close()
  
  if test_result:match('error') or test_result:match('invalid') then
    print("❌ Command error: " .. test_result)
  else
    print("✓ Command structure looks valid")
    print("Sample output: " .. test_result:sub(1, 200))
  end
else
  print("❌ ripgrep not found")
end
