# Simple Process Ownership on AO

This package facilitates the development of AO processes that require the ability to

- manage ownership of the process
- gate access to handlers based on process ownership

## Features

1. An access control check based on **native process ownership** on AO. 
2. Ownership transfer
3. Ownership renouncement via the AO [_Ownership Renounce Manager_](https://github.com/Autonomous-Finance/ao-ownership-renounce-manager)

## Installation

```lua
APM.install('@af/ownable')
```

## Usage

1. Require the `ownable` module in your Lua script
2. Execute `ownable.load()`

These steps will add the necessary global state and Handlers.

```lua
-- process.lua

local ownable = require("@af/ownable")

ownable.load()
```

## Conflict Considerations

⚠️ ❗️ Be mindful of potential conflicts in terms of **global state** and the **`Handlers.list`**

Both your application code and other packages you install via APM, can potentially conflict with this package.

So, if you decide to use this package, consider the following

```lua
_G.OWNERSHIP_RENOUNCER_PROCESS

Handlers.list = {
  -- ...
  { 
    name = "transferOwnership", 
    -- ... 
  },
  { 
    name = "renounceOwnership", 
    -- ... 
  }
  -- ...
}
```
