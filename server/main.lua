--- oblsk_accounts - Server Main
--- Hooks playerConnecting to resolve the connecting player's Account and
--- reject banned/unresolvable connections before they spawn. See
--- docs/superpowers/specs/2026-08-10-accounts-module-design.md.
print('[oblsk_accounts] Loading...')

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    deferrals.defer()
    Citizen.Wait(0)
    deferrals.update('Checking account...')

    local identifiers = AccountService.parseIdentifiers(GetPlayerIdentifiers(src))

    local ok, accountId, conflicts, err = pcall(AccountService.findOrCreateAccount, identifiers)
    if not ok then
        print('[oblsk_accounts] ERROR resolving account for ' .. name .. ': ' .. tostring(accountId))
        deferrals.done('Could not verify your account. Please try again.')
        return
    end

    if not accountId then
        deferrals.done(err or 'Could not verify your account.')
        return
    end

    if conflicts and #conflicts > 0 then
        for _, conflict in ipairs(conflicts) do
            print('[oblsk_accounts] identifier conflict: ' .. conflict.type .. ':' .. conflict.value ..
                ' expected on account ' .. conflict.expectedAccountId .. ' but already linked to account ' .. conflict.actualAccountId)
        end
    end

    local ban = AccountService.checkBan(accountId, identifiers)
    if ban then
        deferrals.done(AccountService.formatBanMessage(ban))
        return
    end

    AccountService.sessionAccounts[src] = accountId
    deferrals.done()
end)

AddEventHandler('playerDropped', function()
    AccountService.sessionAccounts[source] = nil
end)

print('[oblsk_accounts] Loaded successfully!')
