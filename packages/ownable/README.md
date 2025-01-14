# ownable

## Simple Process Ownership & Access Control on AO

This package facilitates the development of AO processes that require the ability to

- manage ownership of the process
- gate access to handlers based on process ownership

The aim is to make it possible for builders to simply "plug it in", much like one would extend a smart contract in Solidity.

## Version

`1.3.2`

## Features

1. An access control check based on **native process ownership** on AO.
3. Handler to get current owner
4. Ownership transfer
5. Ownership renouncement via the AO [_Ownership Renounce Manager_](https://github.com/Autonomous-Finance/ao-ownership-renounce-manager)

Ownerhip Renounce Manager: `wA4k2u-NqBfBsjbQWq9cWnv2Cn98hB-osDXx9AfPaMA`

### Owner vs Self

A **direct interaction** of the owner with their process can occur in multiple ways
- message sent via *aoconnect* in a node script
- message sent via the *ArConnect* browser extension (aoconnect-bsed)
- message sent through the [AO.LINK UI](https://ao.link), using the "Write" tab on a process page (aoconnect-based)

Unlike on EVM systems, where the owner interacts with the smart contract by sending a transaction directly to it, on AO we also have an **indirect interaction** between owner and process. It is common for an owner to interact with their process by opening it in AOS. Calling a handler of the process through an AOS evaluation like

```lua
Send({Target = ao.id, Action = 'Protected-Handler'})
```

will actually result in an `Eval` message with this code, where the **sender is the process itself**.

This is why, additionally to the expected `Ownable.onlyOwner()`, we've included `Ownable.onlyOwnerOrSelf()` as an option for gating your handlers.

## Usage

This package can be used via APM installation through `aos` or via a pre-build APM download into your project directory.

### APM download & require locally

Install `apm-tool` on your system. This cli tool allows you to download APM packages into your lua project.

```shell
npm i -g apm-tool
```

Downlad the package into your project as a single lua file:

```shell
cd your/project/directory
apm download @autonomousfinance/ownable
cp apm_modules/@autonomousfinance/ownable/source.lua ./ownable.lua
```

Require the file locally from your main process file. 

```lua
Ownable = require("ownable")
```

The code in `example-process.lua` demonstrates how to achieve this. 

📝 Keep in mind, with this approach you will eventually need to amalgamate your `example-process.lua` and `ownable.lua` into a single lua file that can be `.load`ed into your process via AOS. See `package/subscribable/build.sh` for an example of how to achieve this.

### APM install & require from APM

Connect with your process via `aos`. Perform the **steps 1 & 2 from your AOS client terminal**.

1. Install APM in your process

```lua
.load client-tool.lua
```

2. Install this package via APM

```lua
APM.install('@autonomousfinance/ownable')
```

3. Require this package via APM in your Lua script. The resulting table contains the package API. The `require` statement also adds package-specific handlers into the `_G.Handlers.list` of your process.

```lua
Ownable = require("@autonomousfinance/ownable")
```

### After requiring

After the package is required into your main process, you have

 1. additional handlers added to Handlers.list
 2. the ability to use the `ownable` API

```lua
-- ownable API

Ownable.onlyOwner(msg) -- acts like a modifier in Solidity (errors on negative result)

Ownable.onlyOwnerOrSelf(msg) -- acts like a modifier in Solidity (errors on negative result)

Ownable.transferOwnership(newOwner) -- performs the transfer of ownership
```

#### No global state pollution

Except for the `_G.Handlers.list`, the package affects nothing in the global space of your project. For best upgradability, we recommend assigning the required package to a global variable of your process.

## Overriding Functionality

Similarly to extending a smart contract in Solidity, using this package allows builders to change the default functionality as needed.

### 1. You can override handlers added by this package.

Either replace the handler entirely
```lua
Handlers.add(
  'ownable.Transfer-Ownership',
  -- your matcher ,
  -- your handle function
)
```

or override handle functions
```lua
-- handle for "ownable.Transfer-Ownership"
function(msg)
  -- same as before
  Ownable.onlyOwner(msg)
  -- ADDITIONAL condition
  assert(isChristmasEve(msg.Timestamp))
  -- same as before
  Ownable.handleTransferOwnership(msg)
end
```

### 2. You can override more specific API functions of this package.
```lua
local originalTransferOwnership = Ownable.transferOwnership
Ownable.transferOwnership = function(newOwner)
  -- same as before
  originalTransferOwnership(newOwner)
  -- your ADDITIONAL logic
  ao.send({Target = AGGREGATOR_PROCESS, Action = "Owner-Changed", ["New-Owner"] = newOwner})
end
```

## Conflicts in the Global Space

⚠️ ❗️ If overriding handlers is not something you need, be mindful of potential conflicts in terms of the **`Handlers.list`**

Both your application code and other packages you install via APM, can potentially conflict with this package. Consider the following handlers as reserved by this package.

```lua
Handlers.list = {
  -- ...
  { 
    name = "ownable.getOwner", 
    -- ... 
  },
  { 
    name = "ownable.transferOwnership", 
    -- ... 
  },
  { 
    name = "ownable.renounceOwnership", 
    -- ... 
  }
  -- ...
}
```
