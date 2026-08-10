--- Account Model - the stable identity every login identifier resolves to.
--- Deliberately bare: nothing identifying lives here directly, that's what
--- AccountIdentifier is for. See
--- docs/superpowers/specs/2026-08-10-accounts-module-design.md.
Account = BaseModel:extend('accounts')

Account.primaryKey = 'id'
Account.timestamps = true
Account.fillable = {}
Account.hidden = {}

return Account
