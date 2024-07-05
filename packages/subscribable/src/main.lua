local function newmodule(cfg)
  assert(cfg.initial ~= nil, "cfg.initial is required: are you initializing or upgrading?") -- as a bug-safety measure, force the package user to be explicit

  local pkg = cfg.existing or {}

  pkg.version = '1.0.0'

  -- pkg acts like the package "global", bundling the state and API functions of the package

  require "subscriptions" (pkg)

  pkg.PAYMENT_TOKEN = 'Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc'

  Handlers.add(
    "subscribable.Register-Subscriber",
    Handlers.utils.hasMatchingTag("Action", "Register-Subscriber"),
    pkg.handleRegisterSubscriber
  )

  Handlers.add(
    'subscribable.Get-Subscriber',
    Handlers.utils.hasMatchingTag('Action', 'Get-Subscriber'),
    pkg.handleGetSubscriber
  )

  Handlers.add(
    "subscribable.Receive-Payment",
    function(msg)
      return Handlers.utils.hasMatchingTag("Action", "Credit-Notice")(msg)
          and msg.From == pkg.PAYMENT_TOKEN
    end,
    pkg.handleReceivePayment
  )

  Handlers.add(
    "subscribable.Get-Available-Topics",
    Handlers.utils.hasMatchingTag("Action", "Get-Available-Topics"),
    pkg.handleGetAvailableTopics
  )

  Handlers.add(
    'subscribable.Subscribe-To-Topics',
    Handlers.utils.hasMatchingTag('Action', 'Subscribe-To-Topics'),
    pkg.handleSubscribeToTopics
  )

  Handlers.add(
    'subscribable.Unsubscribe-From-Topics',
    Handlers.utils.hasMatchingTag('Action', 'Unsubscribe-From-Topics'),
    pkg.handleUnsubscribeFromTopics
  )

  return pkg
end
return newmodule
