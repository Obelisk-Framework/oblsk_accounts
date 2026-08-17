-- core/modules/oblsk_accounts/tests/account_service_moderation_spec.lua
-- Run from the repository root:  lua5.4 modules/oblsk_accounts/tests/account_service_moderation_spec.lua
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
dofile(CORE_ROOT .. '/core/server/Models/Permission.lua')
dofile(CORE_ROOT .. '/core/server/Services/PermissionService.lua')
dofile(CORE_ROOT .. '/core/server/Traits/HasPermissions.lua')
dofile(scriptDir .. '../server/models/Account.lua')
dofile(scriptDir .. '../server/models/AccountIdentifier.lua')
dofile(scriptDir .. '../server/models/Ban.lua')
dofile(scriptDir .. '../server/models/ModerationLog.lua')
dofile(CORE_ROOT .. '/modules/oblsk_characters/server/models/Character.lua')
dofile(scriptDir .. '../server/services/AccountService.lua')

local makeFakeQueryBuilderModule = dofile(scriptDir .. 'support/fake_query_builder.lua')

local tests, failures, passed = {}, {}, 0
local function test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end
local function eq(actual, expected, msg)
    if actual ~= expected then
        error(string.format('%s\n     expected: %s\n     actual:   %s', msg or 'assertion failed', tostring(expected), tostring(actual)), 2)
    end
end
local function truthy(v, msg) if not v then error(msg or 'expected truthy', 2) end end

local function withFakeDb(fn)
    local tables = {}
    local original = QueryBuilder
    QueryBuilder = makeFakeQueryBuilderModule(tables)
    local ok, err = pcall(fn, tables)
    QueryBuilder = original
    if not ok then error(err, 2) end
end

--------------------------------------------------------------------------------
-- listBans
--------------------------------------------------------------------------------

test('listBans: returns all bans newest first, with display_name from a character', function()
    withFakeDb(function(tables)
        tables.accounts = { { id = 1 } }
        tables.characters = { { id = 10, account_id = 1, first_name = 'Jane', last_name = 'Doe', deleted_at = nil } }
        tables.bans = {
            { id = 1, account_id = 1, reason = 'first', issued_by = '1', created_at = '2026-08-10 00:00:00' },
            { id = 2, account_id = 1, reason = 'second', issued_by = '1', created_at = '2026-08-11 00:00:00' },
        }

        local bans = AccountService.listBans()
        eq(#bans, 2)
        eq(bans[1].reason, 'second', 'newest first')
        eq(bans[1].display_name, 'Jane Doe')
    end)
end)

test('listBans: identifier-only ban has no display_name', function()
    withFakeDb(function(tables)
        tables.bans = { { id = 1, identifier_type = 'ip', identifier_value = '127.0.0.1', reason = 'x', issued_by = '1', created_at = '2026-08-10 00:00:00' } }
        local bans = AccountService.listBans()
        eq(#bans, 1)
        eq(bans[1].display_name, nil)
    end)
end)

--------------------------------------------------------------------------------
-- listModerationLogs
--------------------------------------------------------------------------------

test('listModerationLogs: returns warn/kick rows newest first', function()
    withFakeDb(function(tables)
        tables.moderation_logs = {
            { id = 1, account_id = 1, type = 'warn', reason = 'a', issued_by = '1', created_at = '2026-08-10 00:00:00' },
            { id = 2, account_id = 1, type = 'kick', reason = 'b', issued_by = '1', created_at = '2026-08-11 00:00:00' },
        }
        local logs = AccountService.listModerationLogs()
        eq(#logs, 2)
        eq(logs[1].type, 'kick', 'newest first')
    end)
end)

--------------------------------------------------------------------------------
-- warn / logKick
--------------------------------------------------------------------------------

test('warn: inserts a moderation_logs row with type warn', function()
    withFakeDb(function(tables)
        AccountService.warn(1, 'being rude', '99')
        eq(#tables.moderation_logs, 1)
        eq(tables.moderation_logs[1].type, 'warn')
        eq(tables.moderation_logs[1].account_id, 1)
        eq(tables.moderation_logs[1].reason, 'being rude')
        eq(tables.moderation_logs[1].issued_by, '99')
    end)
end)

test('logKick: inserts a moderation_logs row with type kick', function()
    withFakeDb(function(tables)
        AccountService.logKick(1, 'exploiting', '99')
        eq(#tables.moderation_logs, 1)
        eq(tables.moderation_logs[1].type, 'kick')
    end)
end)

print('Running AccountService moderation unit tests\n')
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then passed = passed + 1; print('  ok   - ' .. t.name)
    else failures[#failures + 1] = t.name; print('  FAIL - ' .. t.name); print('         ' .. tostring(err):gsub('\n', '\n         ')) end
end
print(string.format('\n%d passed, %d failed', passed, #failures))
os.exit(#failures == 0 and 0 or 1)
