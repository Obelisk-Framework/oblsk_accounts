--- AccountService (server) - resolves every connecting player to a stable
--- Account reachable through any identifier it has ever used, and checks
--- active bans before the player spawns. See
--- docs/superpowers/specs/2026-08-10-accounts-module-design.md.
AccountService = {}
AccountService.sessionAccounts = {} -- source -> account_id, runtime only, set in playerConnecting, cleared in playerDropped

local function findIdentifier(identifiers, targetType)
    for _, identifier in ipairs(identifiers) do
        if identifier.type == targetType then
            return identifier
        end
    end
    return nil
end

--- Parses FXServer's GetPlayerIdentifiers(source) output ("type:value"
--- strings) into { type, value } pairs. Splits on the FIRST ':' only, since
--- some identifier values can contain their own ':'.
--- @param rawIdentifiers table|nil
--- @return table[] entries shaped { type = string, value = string }
function AccountService.parseIdentifiers(rawIdentifiers)
    local identifiers = {}
    for _, raw in ipairs(rawIdentifiers or {}) do
        local sep = raw:find(':')
        if sep then
            table.insert(identifiers, { type = raw:sub(1, sep - 1), value = raw:sub(sep + 1) })
        end
    end
    return identifiers
end

--- Resolves the account for this connection's identifiers, creating one if
--- the license identifier has never been seen. Every other identifier gets
--- linked if new, touched (last-seen) if already linked to this same
--- account, or reported as a conflict (never merged) if linked to a
--- different account.
--- @param identifiers table[] from parseIdentifiers
--- @return number|nil accountId
--- @return table[]|nil conflicts entries shaped { type, value, expectedAccountId, actualAccountId }
--- @return string|nil err set only when accountId is nil
function AccountService.findOrCreateAccount(identifiers)
    local license = findIdentifier(identifiers, 'license')
    if not license then
        return nil, nil, 'missing license identifier'
    end

    local accountId
    local existing = QueryBuilder.new('account_identifiers')
        :where('type', 'license'):where('value', license.value):firstSync()

    if existing then
        accountId = existing.account_id
    else
        local account = Account:createSync({})
        accountId = account.attributes.id
        AccountIdentifier:createSync({ account_id = accountId, type = 'license', value = license.value })
    end

    local conflicts = {}
    for _, identifier in ipairs(identifiers) do
        if identifier.type ~= 'license' then
            local row = QueryBuilder.new('account_identifiers')
                :where('type', identifier.type):where('value', identifier.value):firstSync()

            if not row then
                AccountIdentifier:createSync({ account_id = accountId, type = identifier.type, value = identifier.value })
            elseif row.account_id == accountId then
                QueryBuilder.new('account_identifiers'):where('id', row.id):update({ updated_at = Database.now() })
            else
                table.insert(conflicts, {
                    type = identifier.type,
                    value = identifier.value,
                    expectedAccountId = accountId,
                    actualAccountId = row.account_id,
                })
            end
        end
    end

    return accountId, conflicts
end

--- Returns the first active (not revoked, not expired) ban matching either
--- accountId or any of the raw identifiers on this connection.
--- @param accountId number|nil
--- @param identifiers table[] from parseIdentifiers
--- @return table|nil ban row
function AccountService.checkBan(accountId, identifiers)
    local now = Database.now()

    local function isActive(ban)
        return ban ~= nil and (ban.expires_at == nil or ban.expires_at > now)
    end

    if accountId then
        local ban = QueryBuilder.new('bans')
            :where('account_id', accountId):whereNull('revoked_at'):firstSync()
        if isActive(ban) then
            return ban
        end
    end

    for _, identifier in ipairs(identifiers) do
        local ban = QueryBuilder.new('bans')
            :where('identifier_type', identifier.type)
            :where('identifier_value', identifier.value)
            :whereNull('revoked_at')
            :firstSync()
        if isActive(ban) then
            return ban
        end
    end

    return nil
end

--- @param target table either { accountId = number } or { type = string, value = string }
--- @param reason string
--- @param issuedBy string
--- @param expiresAt string|nil datetime string, nil = permanent
--- @return Ban
function AccountService.ban(target, reason, issuedBy, expiresAt)
    local attributes = { reason = reason, issued_by = issuedBy, expires_at = expiresAt }
    if target.accountId then
        attributes.account_id = target.accountId
    else
        attributes.identifier_type = target.type
        attributes.identifier_value = target.value
    end
    return Ban:createSync(attributes)
end

--- @param banId number
function AccountService.unban(banId)
    return QueryBuilder.new('bans'):where('id', banId):update({ revoked_at = Database.now() })
end

--- @param ban table a bans row (from checkBan)
--- @return string
function AccountService.formatBanMessage(ban)
    if ban.expires_at then
        return 'Banned: ' .. ban.reason .. ' (expires ' .. ban.expires_at .. ')'
    end
    return 'Banned: ' .. ban.reason .. ' (permanent)'
end

--- @param source number
--- @return number|nil
function AccountService.getAccountId(source)
    return AccountService.sessionAccounts[source]
end

--- Best-effort display name for a ban/log row: the first non-deleted
--- character on that account, or nil if the account has none yet (bans can
--- predate character creation, e.g. an identifier-only ban).
--- @param accountId number|nil
--- @return string|nil
local function characterDisplayName(accountId)
    if not accountId then return nil end
    local character = Character:where('account_id', accountId):whereNull('deleted_at'):firstSync()
    if not character then return nil end
    return character.first_name .. ' ' .. character.last_name
end

--- @return table[] every ban, newest first, each with a best-effort display_name
function AccountService.listBans()
    local rows = QueryBuilder.new('bans'):orderBy('created_at', 'desc'):getSync()
    for _, row in ipairs(rows) do
        row.display_name = characterDisplayName(row.account_id)
    end
    return rows
end

--- @return table[] every warn/kick log row, newest first, each with a best-effort display_name
function AccountService.listModerationLogs()
    local rows = QueryBuilder.new('moderation_logs'):orderBy('created_at', 'desc'):getSync()
    for _, row in ipairs(rows) do
        row.display_name = characterDisplayName(row.account_id)
    end
    return rows
end

--- @param accountId number
--- @param reason string
--- @param issuedBy string
function AccountService.warn(accountId, reason, issuedBy)
    return ModerationLog:createSync({ account_id = accountId, type = 'warn', reason = reason, issued_by = issuedBy })
end

--- @param accountId number
--- @param reason string
--- @param issuedBy string
function AccountService.logKick(accountId, reason, issuedBy)
    return ModerationLog:createSync({ account_id = accountId, type = 'kick', reason = reason, issued_by = issuedBy })
end

return AccountService
