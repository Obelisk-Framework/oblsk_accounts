--- Ban Model - targets either an Account (account_id) or a bare identifier
--- (identifier_type/identifier_value), never both. See the design spec's
--- Schema section for the invariant; not DB-enforced.
Ban = BaseModel:extend('bans')

Ban.primaryKey = 'id'
Ban.timestamps = true
Ban.fillable = { 'account_id', 'identifier_type', 'identifier_value', 'reason', 'issued_by', 'expires_at', 'revoked_at' }
Ban.hidden = {}

function Ban:accountRelation()
    return self:belongsTo(Account, 'account_id', 'id')
end

return Ban
