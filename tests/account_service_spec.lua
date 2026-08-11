--- Unit tests for AccountService: identifier parsing, account resolution
--- (license-wins, conflict-not-merge), ban matching/creation/revocation.
--- Run from the repository root:  lua5.4 tests/account_service_spec.lua
---
--- CORE_ROOT is a relative walk-up from this file to the core repo root.
--- oblsk_accounts must live at <core-root>/modules/oblsk_accounts/ for
--- FXServer to load it as part of core at all, so this file is always
--- three levels below the core root (tests/ -> oblsk_accounts/ -> modules/
--- -> core-root).
local scriptDir = arg[0]:match('(.*/)') or './'
local CORE_ROOT = scriptDir .. '../../..'

dofile(CORE_ROOT .. '/tests/support/fivem_stubs.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Init.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/MySQL.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Dialects/Postgres.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Database.lua')
dofile(CORE_ROOT .. '/core/server/ORM/QueryBuilder.lua')
dofile(CORE_ROOT .. '/core/server/ORM/Schema.lua')
dofile(CORE_ROOT .. '/core/server/ORM/BaseModel.lua')
dofile(CORE_ROOT .. '/core/server/Services/PermissionService.lua')
dofile(CORE_ROOT .. '/core/server/Traits/HasPermissions.lua')
dofile(scriptDir .. '../server/models/Account.lua')
dofile(scriptDir .. '../server/models/AccountIdentifier.lua')
dofile(scriptDir .. '../server/models/Ban.lua')
dofile(scriptDir .. '../server/services/AccountService.lua')

local makeFakeQueryBuilderModule = dofile(scriptDir .. 'support/fake_query_builder.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format('%s\n     expected: %s\n     actual:   %s',
            msg or 'assertion failed', tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, msg)
    if not v then error(msg or 'expected a truthy value', 2) end
end

--- Swaps the real global QueryBuilder for the fake for the duration of fn,
--- so AccountService (and the Account/AccountIdentifier/Ban models it
--- drives via BaseModel:newQuery, which reads the global QueryBuilder at
--- call time) operate on a fresh in-memory table set per test.
local function withFakeDb(fn)
    local tables = {}
    local original = QueryBuilder
    QueryBuilder = makeFakeQueryBuilderModule(tables)

    local ok, err = pcall(fn, tables)

    QueryBuilder = original
    if not ok then error(err, 2) end
end

--------------------------------------------------------------------------------
-- parseIdentifiers
--------------------------------------------------------------------------------

test('parseIdentifiers: splits type:value pairs', function()
    local identifiers = AccountService.parseIdentifiers({ 'license:abc123', 'discord:998877', 'ip:127.0.0.1' })
    eq(#identifiers, 3)
    eq(identifiers[1].type, 'license')
    eq(identifiers[1].value, 'abc123')
    eq(identifiers[3].type, 'ip')
    eq(identifiers[3].value, '127.0.0.1')
end)

test('parseIdentifiers: an empty or nil list returns an empty table', function()
    eq(#AccountService.parseIdentifiers({}), 0)
    eq(#AccountService.parseIdentifiers(nil), 0)
end)

test('parseIdentifiers: ignores malformed entries with no colon', function()
    local identifiers = AccountService.parseIdentifiers({ 'garbage', 'license:abc' })
    eq(#identifiers, 1)
    eq(identifiers[1].type, 'license')
end)

--------------------------------------------------------------------------------
-- findOrCreateAccount
--------------------------------------------------------------------------------

test('findOrCreateAccount: no license identifier returns nil with an error', function()
    withFakeDb(function()
        local accountId, conflicts, err = AccountService.findOrCreateAccount({ { type = 'discord', value = '123' } })
        eq(accountId, nil)
        truthy(err ~= nil, 'expected an error message')
    end)
end)

test('findOrCreateAccount: an unseen license creates a new account and links it', function()
    withFakeDb(function(tables)
        local accountId = AccountService.findOrCreateAccount({ { type = 'license', value = 'abc' } })
        truthy(type(accountId) == 'number', 'accountId is a number')
        eq(#tables.accounts, 1)
        eq(#tables.account_identifiers, 1)
        eq(tables.account_identifiers[1].type, 'license')
        eq(tables.account_identifiers[1].value, 'abc')
        eq(tables.account_identifiers[1].account_id, accountId)
    end)
end)

test('findOrCreateAccount: a known license resolves to the same existing account, no duplicate row', function()
    withFakeDb(function(tables)
        local firstId = AccountService.findOrCreateAccount({ { type = 'license', value = 'abc' } })
        local secondId = AccountService.findOrCreateAccount({ { type = 'license', value = 'abc' } })
        eq(secondId, firstId)
        eq(#tables.accounts, 1)
    end)
end)

test('findOrCreateAccount: a new secondary identifier on a known account gets linked', function()
    withFakeDb(function(tables)
        local accountId = AccountService.findOrCreateAccount({
            { type = 'license', value = 'abc' },
            { type = 'discord', value = 'd1' },
        })
        eq(#tables.account_identifiers, 2)

        local discordRow
        for _, row in ipairs(tables.account_identifiers) do
            if row.type == 'discord' then discordRow = row end
        end
        truthy(discordRow ~= nil, 'discord identifier was linked')
        eq(discordRow.account_id, accountId)
    end)
end)

test('findOrCreateAccount: a secondary identifier already linked to a different account is a conflict, never merged', function()
    withFakeDb(function(tables)
        local accountA = AccountService.findOrCreateAccount({
            { type = 'license', value = 'license-a' },
            { type = 'discord', value = 'shared-discord' },
        })
        local accountB, conflicts = AccountService.findOrCreateAccount({
            { type = 'license', value = 'license-b' },
            { type = 'discord', value = 'shared-discord' },
        })

        truthy(accountB ~= accountA, 'a different license always resolves to a different account')
        eq(#conflicts, 1)
        eq(conflicts[1].type, 'discord')
        eq(conflicts[1].expectedAccountId, accountB)
        eq(conflicts[1].actualAccountId, accountA)

        local discordLinks = 0
        for _, row in ipairs(tables.account_identifiers) do
            if row.type == 'discord' and row.value == 'shared-discord' then
                discordLinks = discordLinks + 1
            end
        end
        eq(discordLinks, 1, 'the conflicting identifier was never duplicated or reassigned')
    end)
end)

--------------------------------------------------------------------------------
-- checkBan / ban / unban
--------------------------------------------------------------------------------

test('checkBan: returns nil when there are no bans', function()
    withFakeDb(function()
        eq(AccountService.checkBan(1, {}), nil)
    end)
end)

test('checkBan: matches an active ban by account_id', function()
    withFakeDb(function()
        AccountService.ban({ accountId = 1 }, 'cheating', 'admin', nil)
        local ban = AccountService.checkBan(1, {})
        truthy(ban ~= nil, 'ban found')
        eq(ban.reason, 'cheating')
    end)
end)

test('checkBan: matches an active ban by raw identifier', function()
    withFakeDb(function()
        AccountService.ban({ type = 'ip', value = '1.2.3.4' }, 'evasion', 'admin', nil)
        local ban = AccountService.checkBan(nil, { { type = 'ip', value = '1.2.3.4' } })
        truthy(ban ~= nil, 'ban found')
    end)
end)

test('checkBan: ignores a revoked ban', function()
    withFakeDb(function()
        local ban = AccountService.ban({ accountId = 1 }, 'cheating', 'admin', nil)
        AccountService.unban(ban.attributes.id)
        eq(AccountService.checkBan(1, {}), nil)
    end)
end)

test('checkBan: ignores an expired ban', function()
    withFakeDb(function()
        AccountService.ban({ accountId = 1 }, 'cheating', 'admin', '2000-01-01 00:00:00')
        eq(AccountService.checkBan(1, {}), nil)
    end)
end)

test('checkBan: a permanent (nil expires_at) ban still matches', function()
    withFakeDb(function()
        AccountService.ban({ accountId = 1 }, 'cheating', 'admin', nil)
        truthy(AccountService.checkBan(1, {}) ~= nil, 'permanent ban matches')
    end)
end)

--------------------------------------------------------------------------------
-- formatBanMessage
--------------------------------------------------------------------------------

test('formatBanMessage: permanent ban', function()
    eq(AccountService.formatBanMessage({ reason = 'cheating', expires_at = nil }), 'Banned: cheating (permanent)')
end)

test('formatBanMessage: temporary ban includes the expiry', function()
    eq(AccountService.formatBanMessage({ reason = 'spam', expires_at = '2026-01-01 00:00:00' }),
        'Banned: spam (expires 2026-01-01 00:00:00)')
end)

--------------------------------------------------------------------------------
-- session map
--------------------------------------------------------------------------------

test('getAccountId: returns nil for an unresolved source', function()
    eq(AccountService.getAccountId(999), nil)
end)

test('getAccountId: returns the account id once set', function()
    AccountService.sessionAccounts[42] = 7
    eq(AccountService.getAccountId(42), 7)
    AccountService.sessionAccounts[42] = nil
end)

--------------------------------------------------------------------------------
-- Runner
--------------------------------------------------------------------------------
print('Running AccountService unit tests\n')
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        print('  ok   - ' .. t.name)
    else
        failures[#failures + 1] = t.name
        print('  FAIL - ' .. t.name)
        print('         ' .. tostring(err):gsub('\n', '\n         '))
    end
end

print(string.format('\n%d passed, %d failed', passed, #failures))
os.exit(#failures == 0 and 0 or 1)
