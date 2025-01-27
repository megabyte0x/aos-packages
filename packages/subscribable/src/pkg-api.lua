local json = require("json")
local bint = require(".bint")(256)

local function newmodule(pkg)
  --[[
    {
      topic: string = eventCheckFn: () => boolean
    }
  ]]
  pkg.TopicsAndChecks = pkg.TopicsAndChecks or {}


  pkg.PAYMENT_TOKEN = '8p7ApPZxC_37M06QHVejCQrKsHbcJEerd3jWNkDUWPQ'
  pkg.PAYMENT_TOKEN_TICKER = 'BRKTST'


  -- REGISTRATION

  function pkg.sendReply(msg, data, tags)
    msg.reply({
      Action = msg.Tags.Action .. "-Response",
      Tags = tags,
      Data = json.encode(data)
    })
  end

  function pkg.sendConfirmation(target, action, tags)
    ao.send({
      Target = target,
      Action = action .. "-Confirmation",
      Tags = tags,
      Status = 'OK'
    })
  end

  function pkg.registerSubscriber(processId, whitelisted)
    local subscriberData = pkg._storage.getSubscriber(processId)

    if subscriberData then
      error('Process ' ..
        processId ..
        ' is already registered as a subscriber.')
    end

    pkg._storage.registerSubscriber(processId, whitelisted)

    pkg.sendConfirmation(
      processId,
      'Register-Subscriber',
      { Whitelisted = tostring(whitelisted) }
    )
  end

  function pkg.handleRegisterSubscriber(msg)
    local processId = msg.From

    pkg.registerSubscriber(processId, false)
    pkg._subscribeToTopics(msg, processId)
  end

  function pkg.handleRegisterWhitelistedSubscriber(msg)
    if msg.From ~= Owner and msg.From ~= ao.id then
      error('Only the owner or the process itself is allowed to register whitelisted subscribers')
    end

    local processId = msg.Tags['Subscriber-Process-Id']

    if not processId then
      error('Subscriber-Process-Id is required')
    end

    pkg.registerSubscriber(processId, true)
    pkg._subscribeToTopics(msg, processId)
  end

  function pkg.handleGetSubscriber(msg)
    local processId = msg.Tags['Subscriber-Process-Id']
    local replyData = pkg._storage.getSubscriber(processId)
    pkg.sendReply(msg, replyData)
  end

  pkg.updateBalance = function(processId, amount, isCredit)
    local subscriber = pkg._storage.getSubscriber(processId)
    if not isCredit and not subscriber then
      error('Subscriber ' .. processId .. ' is not registered. Register first, then make a payment')
    end

    if not isCredit and bint(subscriber.balance) < bint(amount) then
      error('Insufficient balance for subscriber ' .. processId .. ' to be debited')
    end

    pkg._storage.updateBalance(processId, amount, isCredit)
  end

  function pkg.handleReceivePayment(msg)
    local processId = msg.Tags["X-Subscriber-Process-Id"]

    local error
    if not processId then
      error = "No subscriber specified"
    end

    if msg.From ~= pkg.PAYMENT_TOKEN then
      error = "Wrong token. Payment token is " .. (pkg.PAYMENT_TOKEN or "?")
    end

    if error then
      ao.send({
        Target = msg.From,
        Action = 'Transfer',
        Recipient = msg.Sender,
        Quantity = msg.Quantity,
        ["X-Action"] = "Subscription-Payment-Refund",
        ["X-Details"] = error
      })

      ao.send({
        Target = msg.Sender,
        Action = "Pay-For-Subscription-Error",
        Status = "ERROR",
        Error = error
      })
      return
    end

    pkg.updateBalance(msg.Tags.Sender, msg.Tags.Quantity, true)

    pkg.sendConfirmation(msg.Sender, 'Pay-For-Subscription')

    print('Received subscription payment from ' ..
      msg.Tags.Sender .. ' of ' .. msg.Tags.Quantity .. ' ' .. msg.From .. " (" .. pkg.PAYMENT_TOKEN_TICKER .. ")")
  end

  function pkg.handleSetPaymentToken(msg)
    pkg.PAYMENT_TOKEN = msg.Tags.Token
  end

  -- TOPICS

  function pkg.configTopicsAndChecks(cfg)
    pkg.TopicsAndChecks = cfg
  end

  function pkg.getTopicsInfo()
    local topicsInfo = {}
    for topic, _ in pairs(pkg.TopicsAndChecks) do
      local topicInfo = pkg.TopicsAndChecks[topic]
      topicsInfo[topic] = {
        description = topicInfo.description,
        returns = topicInfo.returns,
        subscriptionBasis = topicInfo.subscriptionBasis
      }
    end

    return topicsInfo
  end

  function pkg.getInfo()
    return {
      paymentTokenTicker = pkg.PAYMENT_TOKEN_TICKER,
      paymentToken = pkg.PAYMENT_TOKEN,
      topics = pkg.getTopicsInfo()
    }
  end

  -- SUBSCRIPTIONS

  function pkg._subscribeToTopics(msg, processId)
    assert(msg.Tags['Topics'], 'Topics is required')

    local topics = json.decode(msg.Tags['Topics'])

    pkg.onlyRegisteredSubscriber(processId)

    pkg._storage.subscribeToTopics(processId, topics)

    local subscriber = pkg._storage.getSubscriber(processId)

    pkg.sendConfirmation(
      processId,
      'Subscribe-To-Topics',
      { ["Updated-Topics"] = json.encode(subscriber.topics) }
    )
  end

  -- same for regular and whitelisted subscriptions - the subscriber must call it
  function pkg.handleSubscribeToTopics(msg)
    local processId = msg.From
    pkg._subscribeToTopics(msg, processId)
  end

  function pkg.unsubscribeFromTopics(processId, topics)
    pkg.onlyRegisteredSubscriber(processId)

    pkg._storage.unsubscribeFromTopics(processId, topics)

    local subscriber = pkg._storage.getSubscriber(processId)

    pkg.sendConfirmation(
      processId,
      'Unsubscribe-From-Topics',
      { ["Updated-Topics"] = json.encode(subscriber.topics) }
    )
  end

  function pkg.handleUnsubscribeFromTopics(msg)
    assert(msg.Tags['Topics'], 'Topics is required')

    local processId = msg.From
    local topics = msg.Tags['Topics']

    pkg.unsubscribeFromTopics(processId, topics)
  end

  -- NOTIFICATIONS

  -- core dispatch functionality

  function pkg.notifySubscribers(topic, payload)
    local targets = pkg._storage.getTargetsForTopic(topic)
    for _, target in ipairs(targets) do
      ao.send({
        Target = target,
        Action = 'Notify-On-Topic',
        Topic = topic,
        Data = json.encode(payload)
      })
    end
  end

  -- notify without check

  function pkg.notifyTopics(topicsAndPayloads, timestamp)
    for topic, payload in pairs(topicsAndPayloads) do
      payload.timestamp = timestamp
      pkg.notifySubscribers(topic, payload)
    end
  end

  function pkg.notifyTopic(topic, payload, timestamp)
    return pkg.notifyTopics({
      [topic] = payload
    }, timestamp)
  end

  -- notify with configured checks

  function pkg.checkNotifyTopics(topics, timestamp)
    for _, topic in ipairs(topics) do
      local shouldNotify = pkg.TopicsAndChecks[topic].checkFn()
      if shouldNotify then
        local payload = pkg.TopicsAndChecks[topic].payloadFn()
        payload.timestamp = timestamp
        pkg.notifySubscribers(topic, payload)
      end
    end
  end

  function pkg.checkNotifyTopic(topic, timestamp)
    return pkg.checkNotifyTopics({ topic }, timestamp)
  end

  -- HELPERS

  pkg.onlyRegisteredSubscriber = function(processId)
    local subscriberData = pkg._storage.getSubscriber(processId)
    if not subscriberData then
      error('process ' .. processId .. ' is not registered as a subscriber')
    end
  end
end

return newmodule
