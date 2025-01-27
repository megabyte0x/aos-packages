do
local _ENV = _ENV
package.preload[ "subscribable" ] = function( ... ) local arg = _G.arg;
package.loaded["pkg-api"] = nil
package.loaded["storage-vanilla"] = nil
package.loaded["storage-db"] = nil
do
local _ENV = _ENV
package.preload[ "pkg-api" ] = function( ... ) local arg = _G.arg;
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
end
end

do
local _ENV = _ENV
package.preload[ "storage-db" ] = function( ... ) local arg = _G.arg;
local sqlite3 = require("lsqlite3")
local bint = require(".bint")(256)
local json = require("json")

local function newmodule(pkg)
  local mod = {}
  pkg._storage = mod

  local sql = {}

  DB = DB or sqlite3.open_memory()

  sql.create_subscribers_table = [[
    CREATE TABLE IF NOT EXISTS subscribers (
        process_id TEXT PRIMARY KEY,
        topics TEXT,  -- treated as JSON (an array of strings)
        balance TEXT,
        whitelisted INTEGER NOT NULL, -- 0 or 1 (false or true)
    );
  ]]

  local function createTableIfNotExists()
    DB:exec(sql.create_subscribers_table)
    print("Err: " .. DB:errmsg())
  end

  createTableIfNotExists()

  -- REGISTRATION & BALANCES

  ---@param whitelisted boolean
  function mod.registerSubscriber(processId, whitelisted)
    local stmt = DB:prepare [[
    INSERT INTO subscribers (process_id, balance, whitelisted)
    VALUES (:process_id, :balance, :whitelisted)
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for registering process: " .. DB:errmsg())
    end
    stmt:bind_names({
      process_id = processId,
      balance = "0",
      whitelisted = whitelisted and 1 or 0
    })
    local _, err = stmt:step()
    stmt:finalize()
    if err then
      error("Err: " .. DB:errmsg())
    end
  end

  function mod.getSubscriber(processId)
    local stmt = DB:prepare [[
    SELECT * FROM subscribers WHERE process_id = :process_id
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for checking subscriber: " .. DB:errmsg())
    end
    stmt:bind_names({ process_id = processId })
    local result = sql.queryOne(stmt)
    if result then
      result.whitelisted = result.whitelisted == 1
      result.topics = json.decode(result.topics)
    end
    return result
  end

  function sql.updateBalance(processId, amount, isCredit)
    local currentBalance = bint(sql.getBalance(processId))
    local diff = isCredit and bint(amount) or -bint(amount)
    local newBalance = tostring(currentBalance + diff)

    local stmt = DB:prepare [[
    UPDATE subscribers
    SET balance = :new_balance
    WHERE process_id = :process_id
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for updating balance: " .. DB:errmsg())
    end
    stmt:bind_names({
      process_id = processId,
      new_balance = newBalance,
    })
    local result, err = stmt:step()
    stmt:finalize()
    if err then
      error("Error updating balance: " .. DB:errmsg())
    end
  end

  function sql.getBalance(processId)
    local stmt = DB:prepare [[
    SELECT * FROM subscribers WHERE process_id = :process_id
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for getting balance entry: " .. DB:errmsg())
    end
    stmt:bind_names({ process_id = processId })
    local row = sql.queryOne(stmt)
    return row and row.balance or "0"
  end

  -- SUBSCRIPTION

  function sql.subscribeToTopics(processId, topics)
    -- add the topics to the existing topics while avoiding duplicates
    local stmt = DB:prepare [[
    UPDATE subscribers
    SET topics = (
        SELECT json_group_array(topic)
        FROM (
            SELECT json_each.value as topic
            FROM subscribers, json_each(subscribers.topics)
            WHERE process_id = :process_id

            UNION

            SELECT json_each.value as topic
            FROM json_each(:topics)
        )
    )
    WHERE process_id = :process_id;
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for subscribing to topics: " .. DB:errmsg())
    end
    stmt:bind_names({
      process_id = processId,
      topic = topics
    })
    local _, err = stmt:step()
    stmt:finalize()
    if err then
      error("Err: " .. DB:errmsg())
    end
  end

  function sql.unsubscribeFromTopics(processId, topics)
    -- remove the topics from the existing topics
    local stmt = DB:prepare [[
    UPDATE subscribers
    SET topics = (
        SELECT json_group_array(topic)
        FROM (
            SELECT json_each.value as topic
            FROM subscribers, json_each(subscribers.topics)
            WHERE process_id = :process_id

            EXCEPT

            SELECT json_each.value as topic
            FROM json_each(:topics)
        )
    )
    WHERE process_id = :process_id;
  ]]
    if not stmt then
      error("Failed to prepare SQL statement for unsubscribing from topics: " .. DB:errmsg())
    end
    stmt:bind_names({
      process_id = processId,
      topic = topics
    })
    local _, err = stmt:step()
    stmt:finalize()
    if err then
      error("Err: " .. DB:errmsg())
    end
  end

  -- NOTIFICATIONS

  function mod.activationCondition()
    return [[
    (subs.whitelisted = 1 OR subs.balance <> "0")
  ]]
  end

  function sql.getTargetsForTopic(topic)
    local activationCondition = mod.activationCondition()
    local stmt = DB:prepare [[
    SELECT process_id
    FROM subscribers as subs
    WHERE json_contains(topics, :topic) AND ]] .. activationCondition

    if not stmt then
      error("Failed to prepare SQL statement for getting notifiable subscribers: " .. DB:errmsg())
    end
    stmt:bind_names({ topic = topic })
    return sql.queryMany(stmt)
  end

  -- UTILS

  function sql.queryMany(stmt)
    local rows = {}
    for row in stmt:nrows() do
      table.insert(rows, row)
    end
    stmt:reset()
    return rows
  end

  function sql.queryOne(stmt)
    return sql.queryMany(stmt)[1]
  end

  function sql.rawQuery(query)
    local stmt = DB:prepare(query)
    if not stmt then
      error("Err: " .. DB:errmsg())
    end
    return sql.queryMany(stmt)
  end

  return sql
end

return newmodule
end
end

do
local _ENV = _ENV
package.preload[ "storage-vanilla" ] = function( ... ) local arg = _G.arg;
local bint = require ".bint" (256)
local json = require "json"
local utils = require ".utils"

local function newmodule(pkg)
  local mod = {
    Subscribers = pkg._storage and pkg._storage.Subscribers or {} -- we preserve state from previously used package
  }

  --[[
    mod.Subscribers :
    {
      processId: ID = {
        topics: string, -- JSON (string representation of a string[])
        balance: string,
        whitelisted: number -- 0 or 1 -- if 1, receives data without the need to pay
      }
    }
  ]]

  pkg._storage = mod

  -- REGISTRATION & BALANCES

  function mod.registerSubscriber(processId, whitelisted)
    mod.Subscribers[processId] = mod.Subscribers[processId] or {
      balance = "0",
      topics = json.encode({}),
      whitelisted = whitelisted and 1 or 0,
    }
  end

  function mod.getSubscriber(processId)
    local data = json.decode(json.encode(mod.Subscribers[processId]))
    if data then
      data.whitelisted = data.whitelisted == 1
      data.topics = json.decode(data.topics)
    end
    return data
  end

  function mod.updateBalance(processId, amount, isCredit)
    local current = bint(mod.Subscribers[processId].balance)
    local diff = isCredit and bint(amount) or -bint(amount)
    mod.Subscribers[processId].balance = tostring(current + diff)
  end

  -- SUBSCRIPTIONS

  function mod.subscribeToTopics(processId, topics)
    local existingTopics = json.decode(mod.Subscribers[processId].topics)

    for _, topic in ipairs(topics) do
      if not utils.includes(topic, existingTopics) then
        table.insert(existingTopics, topic)
      end
    end
    mod.Subscribers[processId].topics = json.encode(existingTopics)
  end

  function mod.unsubscribeFromTopics(processId, topics)
    local existingTopics = json.decode(mod.Subscribers[processId].topics)
    for _, topic in ipairs(topics) do
      existingTopics = utils.filter(
        function(t)
          return t ~= topic
        end,
        existingTopics
      )
    end
    mod.Subscribers[processId].topics = json.encode(existingTopics)
  end

  -- NOTIFICATIONS

  function mod.getTargetsForTopic(topic)
    local targets = {}
    for processId, v in pairs(mod.Subscribers) do
      local mayReceiveNotification = mod.hasEnoughBalance(processId) or v.whitelisted == 1
      if mod.isSubscribedTo(processId, topic) and mayReceiveNotification then
        table.insert(targets, processId)
      end
    end
    return targets
  end

  -- HELPERS

  mod.hasEnoughBalance = function(processId)
    return mod.Subscribers[processId] and bint(mod.Subscribers[processId].balance) > 0
  end

  mod.isSubscribedTo = function(processId, topic)
    local subscription = mod.Subscribers[processId]
    if not subscription then return false end

    local topics = json.decode(subscription.topics)
    for _, subscribedTopic in ipairs(topics) do
      if subscribedTopic == topic then
        return true
      end
    end
    return false
  end
end

return newmodule
end
end

local function newmodule(cfg)
  local isInitial = Subscribable == nil

  -- for bug-prevention, force the package user to be explicit on initial require
  assert(not isInitial or cfg and cfg.useDB ~= nil,
    "cfg.useDb is required: are you using the sqlite version (true) or the Lua-table based version (false)?")

  local pkg = Subscribable or
      { useDB = cfg.useDB } -- useDB can only be set on initialization; afterwards it remains the same

  pkg.version = '1.3.8'

  -- pkg acts like the package "global", bundling the state and API functions of the package

  if pkg.useDB then
    require "storage-db" (pkg)
  else
    require "storage-vanilla" (pkg)
  end

  require "pkg-api" (pkg)

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
          and Handlers.utils.hasMatchingTag("X-Action", "Pay-For-Subscription")(msg)
    end,
    pkg.handleReceivePayment
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
end
end

--[[
  EXAMPLE PROCESS

  This Process tracks a Counter and a Greeting that can be publicly updated.

  It is also required to be subscribable.

  EVENTS that are interesting to subscribers
    - Counter is even
    - Greeting contains "gm" / "GM" / "gM" / "Gm"

  HANDLERS that may trigger the events
    - "increment" -> Counter is incremented
    - "setGreeting" -> Greeting is set
    - "setGreetingAsGmVariant" -> Greeting is set as a randomly generated variant of "GM"
    - "updateAll" -> Counter and Greeting are updated
]]

Counter = Counter or 0

Greeting = Greeting or "Hello"

package.loaded['subscribable'] = nil
if not Subscribable then
  -- INITIAL DEPLOYMENT of example.lua

  Subscribable = require 'subscribable' ({ -- when using the package with APM, require '@autonomousfinance/subscribable'
    useDB = false
  })
else
  -- UPGRADE of example.lua

  -- We reuse all existing package state
  Subscribable = require 'subscribable' () -- when using the package with APM, require '@autonomousfinance/subscribable'
end

Handlers.add(
  'Increment',
  Handlers.utils.hasMatchingTag('Action', 'Increment'),
  function(msg)
    Counter = Counter + 1
    -- Check and send notifications if event occurs
    Subscribable.checkNotifyTopic('even-counter', msg.Timestamp)
  end
)

Handlers.add(
  'Set-Greeting',
  Handlers.utils.hasMatchingTag('Action', 'Set-Greeting'),
  function(msg)
    Greeting = msg.Tags.Greeting
    -- Check and send notifications if event occurs
    Subscribable.checkNotifyTopic('gm-greeting', msg.Timestamp)
  end
)

Handlers.add(
  'Set-Greeting-As-Gm-Variant',
  Handlers.utils.hasMatchingTag('Action', 'Set-Greeting-As-Gm-Variant'),
  function(msg)
    Greeting = 'GM-' .. tostring(math.random(1000, 9999))
    -- We know for sure that notifications should be sent --> this helps to avoid performing redundant computation
    Subscribable.notifyTopic('gm-greeting', { greeting = Greeting }, msg.Timestamp)
  end
)

Handlers.add(
  'Update-All',
  Handlers.utils.hasMatchingTag('Action', 'Update-All'),
  function(msg)
    Greeting = msg.Tags.Greeting
    Counter = msg.Tags.Counter
    -- Check for multiple topics and send notifications if event occurs
    Subscribable.checkNotifyTopics(
      { 'even-counter', 'gm-greeting' },
      msg.Timestamp
    )
  end
)

Handlers.add(
  'Whitelist-Subscriber',
  Handlers.utils.hasMatchingTag('Action', 'Whitelist-Subscriber'),
  function(msg)
    assert(msg.From == Owner or msg.From == ao.id, 'Only the owner can whitelist a subscriber')
    Subscribable._storage.Subscribers[msg.Tags['Process-ID']].whitelisted = 1
  end
)

-- CONFIGURE TOPICS AND CHECKS

-- We define CUSTOM TOPICS and corresponding CHECK FUNCTIONS
-- Check Functions use global state of this process (example.lua)
-- in order to determine if the event is occurring

local checkNotifyEvenCounter = function()
  return Counter % 2 == 0
end

local payloadForEvenCounter = function()
  return { counter = Counter }
end

local checkNotifyGreeting = function()
  return string.find(string.lower(Greeting), "gm")
end

local payloadForGreeting = function()
  return { greeting = Greeting }
end

Subscribable.configTopicsAndChecks({
  ['even-counter'] = {
    checkFn = checkNotifyEvenCounter,
    payloadFn = payloadForEvenCounter,
    description = 'Counter is even',
    returns = '{ "counter" : number }',
    subscriptionBasis = "Payment of 1 " .. Subscribable.PAYMENT_TOKEN_TICKER
  },
  ['gm-greeting'] = {
    checkFn = checkNotifyGreeting,
    payloadFn = payloadForGreeting,
    description = 'Greeting contains "gm" (any casing)',
    returns = '{ "greeting" : string }',
    subscriptionBasis = "Payment of 1 " .. Subscribable.PAYMENT_TOKEN_TICKER
  }
})
