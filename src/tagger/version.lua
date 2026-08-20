--[[
  The plugin version, and the single source of truth for it.

  Semantic versioning (https://semver.org): MAJOR.MINOR.PATCH.
    MAJOR - a change that makes an existing .usdx-user-tags.yaml unreadable to
            this plugin, or changes the meaning of what is already written
    MINOR - new capability that older files and older readers still cope with
    PATCH - fixes only, no format or behaviour change

  This value is used in three places, which is why it lives alone:
    - register() in the plugin, so UltraStar lists it
    - the "version:" field of every tag file this plugin writes
    - the generated bundle header
]]

return '0.1.0'
