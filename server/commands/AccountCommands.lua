--- oblsk_accounts - Admin Commands
--- Minimum viable surface for writing to the bans table: without these,
--- issuing or revoking a ban needs raw SQL. Not a moderation UI.
local function isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(source, 'admin')
end

RegisterCommand('ban', function(source, args)
    if not isAdmin(source) then return end

    local targetId = tonumber(args[1])
    local reason = table.concat(args, ' ', 2)
    if not targetId or reason == '' then
        print('Usage: /ban <serverId> <reason>')
        return
    end

    local accountId = AccountService.getAccountId(targetId)
    if not accountId then
        print('[oblsk_accounts] player ' .. targetId .. ' has no resolved account')
        return
    end

    AccountService.ban({ accountId = accountId }, reason, tostring(source), nil)
    DropPlayer(targetId, 'Banned: ' .. reason)
end, false)

RegisterCommand('tempban', function(source, args)
    if not isAdmin(source) then return end

    local targetId = tonumber(args[1])
    local minutes = tonumber(args[2])
    local reason = table.concat(args, ' ', 3)
    if not targetId or not minutes or reason == '' then
        print('Usage: /tempban <serverId> <minutes> <reason>')
        return
    end

    local accountId = AccountService.getAccountId(targetId)
    if not accountId then
        print('[oblsk_accounts] player ' .. targetId .. ' has no resolved account')
        return
    end

    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + minutes * 60)
    AccountService.ban({ accountId = accountId }, reason, tostring(source), expiresAt)
    DropPlayer(targetId, 'Banned: ' .. reason)
end, false)

RegisterCommand('banid', function(source, args)
    if not isAdmin(source) then return end

    local idType = args[1]
    local idValue = args[2]
    local reason = table.concat(args, ' ', 3)
    if not idType or not idValue or reason == '' then
        print('Usage: /banid <type> <value> <reason>')
        return
    end

    AccountService.ban({ type = idType, value = idValue }, reason, tostring(source), nil)
    print('[oblsk_accounts] banned ' .. idType .. ':' .. idValue)
end, false)

RegisterCommand('unban', function(source, args)
    if not isAdmin(source) then return end

    local banId = tonumber(args[1])
    if not banId then
        print('Usage: /unban <banId>')
        return
    end

    AccountService.unban(banId)
    print('[oblsk_accounts] revoked ban #' .. banId)
end, false)
