--- Migration: Create bans table
return {
    up = function()
        Schema.create('bans', function(table)
            table:id()
            table:integer('account_id')
            table:string('identifier_type', 50)
            table:string('identifier_value', 255)
            table:text('reason'):notNullable()
            table:string('issued_by', 255):notNullable()
            table:datetime('expires_at')
            table:datetime('revoked_at')
            table:timestamps()

            table:index({'account_id'})
            table:index({'identifier_type', 'identifier_value'})
            table:foreign('account_id'):references('id'):on('accounts'):onDelete('CASCADE')
        end)

        print('[Migration] Created bans table')
    end,

    down = function()
        Schema.drop('bans')
        print('[Migration] Dropped bans table')
    end
}
