--- AccountIdentifier Model - one login identifier (license, discord, steam,
--- ip, ...) linked to an Account. unique(type, value) at the DB level: one
--- identifier value can only ever belong to one account.
AccountIdentifier = BaseModel:extend('account_identifiers')

AccountIdentifier.primaryKey = 'id'
AccountIdentifier.timestamps = true
AccountIdentifier.fillable = { 'account_id', 'type', 'value' }
AccountIdentifier.hidden = {}

function AccountIdentifier:accountRelation()
    return self:belongsTo(Account, 'account_id', 'id')
end

return AccountIdentifier
