--- Migration: Create accounts table
return {
    up = function()
        Schema.create('accounts', function(table)
            table:id()
            table:timestamps()
        end)

        print('[Migration] Created accounts table')
    end,

    down = function()
        Schema.drop('accounts')
        print('[Migration] Dropped accounts table')
    end
}
