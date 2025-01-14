local function newmodule(cfg)
  local pkg = Ownable or {}

  local isInitial = Ownable == nil
  if isInitial then
    pkg.Owners = {
      [Owner] = true,
    }
    if cfg and cfg.otherOwners then
      for _, owner in ipairs(cfg.otherOwners) do
        pkg.Owners[owner] = true
      end
    end
  end

  pkg.version = '1.3.3'

  local json = require "json"

  pkg.RENOUNCE_MANAGER = 'wA4k2u-NqBfBsjbQWq9cWnv2Cn98hB-osDXx9AfPaMA'

  -- HANDLERS

  --[[
  The process Owner changes on each Eval performed by one of the Owners.
  This approach allows for whitelisted wallets to interact with the process
  via the aos CLI as if they are regular owners.
  - Results from query Eval's like `aos> Owner` are displayed immediately in the CLI.
  - The process interface can be shut down and reopened by the whitelisted account
    regardless of who the last Eval caller (most recent process Owner) was
]]

  -- reassign owner if one of the whitelisted owners calls an Eval
  Handlers.prepend(
    'ownable-multi.customEvalMatchPositive',
    function(msg)
      local isEval = Handlers.utils.hasMatchingTag("Action", "Eval")(msg)
      local isWhitelisted = pkg.Owners[msg.From]
      return isEval and isWhitelisted and "continue" or false
    end,
    function(msg)
      Owner = msg.From
    end
  )

  -- error if a non-whitelisted owner calls an Eval
  Handlers.prepend(
    'ownable-multi.customEvalMatchNegative',
    function(msg)
      local isEval = Handlers.utils.hasMatchingTag("Action", "Eval")(msg)
      local isWhitelisted = pkg.Owners[msg.From]
      return isEval and not isWhitelisted
    end,
    function(msg)
      error("Only an owner is allowed")
    end
  )

  Handlers.add(
    "ownable-multi.Get-Owners",
    Handlers.utils.hasMatchingTag("Action", "Get-Owners"),
    function(msg)
      ao.send({ Target = msg.From, Data = json.encode(pkg.getOwnersArray()) })
    end
  )

  Handlers.add(
    "ownable-multi.Add-Owner",
    Handlers.utils.hasMatchingTag("Action", "Add-Owner"),
    function(msg)
      pkg.onlyOwner(msg)
      pkg.handleAddOwner(msg)
    end
  )

  Handlers.add(
    "ownable-multi.Remove-Owner",
    Handlers.utils.hasMatchingTag("Action", "Remove-Owner"),
    function(msg)
      pkg.onlyOwner(msg)
      pkg.handleRemoveOwner(msg)
    end
  )

  --[[
    Renounce ownership altogether -> NONE of the accounts in Owners
    will be able to call owner-gated handlers anymore.
  ]]
  Handlers.add(
    "ownable-multi.Renounce-Ownership",
    Handlers.utils.hasMatchingTag("Action", "Renounce-Ownership"),
    function(msg)
      pkg.onlyOwner(msg)
      pkg.Owners = nil
      Owner = pkg.RENOUNCE_MANAGER
      msg.send({ Target = Owner, Action = 'MakeRenounce' })
    end
  )

  -- API

  pkg.getInfo = function()
    return {
      Owner = Owner
    }
  end

  pkg.onlyOwner = function(msg)
    if pkg.Owners == nil then
      assert(msg.From == Owner, "Only the owner is allowed")
    else
      assert(pkg.Owners[msg.From], "Only an owner is allowed")
    end
  end

  -- useful for interactions via AOS
  pkg.onlyOwnerOrSelf = function(msg)
    if msg.From == ao.id then return end

    pkg.onlyOwner(msg)
  end

  pkg.addOwner = function(newOwner)
    pkg.Owners[newOwner] = true
    ao.send({
      Target = ao.id,
      Event = "Add-Owner",
      ["New-Owner"] = Owner,
      ["Current-Owners"] = json.encode(pkg
        .getOwnersArray())
    })
  end

  pkg.handleAddOwner = function(msg)
    local newOwner = msg.Tags["New-Owner"]
    assert(newOwner ~= nil and type(newOwner) == 'string', '"New-Owner" is required!')
    pkg.addOwner(newOwner)
  end

  pkg.removeOwner = function(oldOwner)
    pkg.Owners[oldOwner] = nil
    ao.send({
      Target = ao.id,
      Event = "Add-Owner",
      ["Old-Owner"] = Owner,
      ["Current-Owners"] = json.encode(pkg
        .getOwnersArray())
    })
  end

  pkg.handleRemoveOwner = function(msg)
    local oldOwner = msg.Tags["Old-Owner"]
    assert(oldOwner ~= nil and type(oldOwner) == 'string', '"Old-Owner" is required!')
    pkg.removeOwner(oldOwner)
  end

  pkg.getOwnersArray = function()
    local ownersArray = {}
    for owner, _ in pairs(pkg.Owners) do
      table.insert(ownersArray, owner)
    end
    return ownersArray
  end


  return pkg
end

return newmodule
