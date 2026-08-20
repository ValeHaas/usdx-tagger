--[[
  Test entry point. Run from the repository root:

      lua spec/run.lua

  No UltraStar Deluxe and no external Lua modules are required: everything
  under test is pure Lua that only touches the filesystem.
]]

package.path = 'src/?.lua;src/?/init.lua;' .. package.path

local runner = require('spec.runner')

local specs = {
  'spec.tagset_spec',
  'spec.tagfile_spec',
  'spec.keys_spec',
  'spec.i18n_spec',
}

io.write('lua: ', _VERSION, '\n\n')

for i = 1, #specs do
  local spec = require(specs[i])
  spec(runner)
end

os.exit(runner.report() and 0 or 1)
