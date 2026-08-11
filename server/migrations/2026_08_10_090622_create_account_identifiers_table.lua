--- Migration: Create account_identifiers table
return {
    up = function()
        Schema.create('account_identifiers', function(table)
            table:id()
            table:integer('account_id')
            table:string('type', 50)
            table:string('value', 255)
            table:timestamps()

            table:unique({'type', 'value'})
            table:index({'account_id'})
            table:foreign('account_id'):references('id'):on('accounts'):onDelete('CASCADE')
        end)

        print('[Migration] Created account_identifiers table')
    end,

    down = function()
        Schema.drop('account_identifiers')
        print('[Migration] Dropped account_identifiers table')
    end
}
