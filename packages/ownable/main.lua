local mod = {
  version = '1.3.2'
}

mod.RENOUNCE_MANAGER = 'wA4k2u-NqBfBsjbQWq9cWnv2Cn98hB-osDXx9AfPaMA'

Handlers.add(
  "ownable.Get-Owner",
  Handlers.utils.hasMatchingTag("Action", "Get-Owner"),
  function(msg)
    ao.send({ Target = msg.From, Data = Owner })
  end
)

Handlers.add(
  "ownable.Transfer-Ownership",
  Handlers.utils.hasMatchingTag("Action", "Transfer-Ownership"),
  function(msg)
    mod.onlyOwner(msg)
    mod.handleTransferOwnership(msg)
  end
)

Handlers.add(
  "ownable.Renounce-Ownership",
  Handlers.utils.hasMatchingTag("Action", "Renounce-Ownership"),
  function(msg)
    mod.onlyOwner(msg)
    Owner = mod.RENOUNCE_MANAGER
    ao.send({ Target = Owner, Action = 'MakeRenounce' })
  end
)

-- API

mod.getInfo = function()
  return {
    Owner = Owner
  }
end

mod.onlyOwner = function(msg)
  assert(msg.From == Owner, "Only the owner is allowed")
end

-- useful for interactions via AOS
mod.onlyOwnerOrSelf = function(msg)
  assert(msg.From == Owner or msg.From == ao.id, "Only the owner or self is allowed")
end

mod.transferOwnership = function(newOwner)
  Owner = newOwner
  ao.send({ Target = ao.id, Event = "Transfer-Ownership", ["New-Owner"] = Owner })
end

mod.handleTransferOwnership = function(msg)
  local newOwner = msg.Tags['New-Owner']
  assert(newOwner ~= nil and type(newOwner) == 'string', 'New-Owner is required!')
  mod.transferOwnership(newOwner)
end

return mod
