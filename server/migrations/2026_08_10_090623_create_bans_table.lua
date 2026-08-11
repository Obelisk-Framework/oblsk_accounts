--- Migration: Create bans table
return {
    up = function()
        Schema.create('bans', function(table)
            table:id()
            table:integer('account_id'):nullable()
            table:string('identifier_type', 50):nullable()
            table:string('identifier_value', 255):nullable()
            table:text('reason')
            table:string('issued_by', 255)
            table:datetime('expires_at'):nullable()
            table:datetime('revoked_at'):nullable()
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
