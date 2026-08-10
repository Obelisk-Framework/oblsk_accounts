# Oblsk_accounts Module

## Description
Resolves every connecting player to a stable Account reachable through any
identifier it has ever used (license, discord, steam, fivem, ip, ...), and
gates connections against active bans before the player spawns.

## Installation
This module loads as part of the `core` resource. After adding it under
`modules/`, run `obelisk registry:generate` from `core/` on the host, then
restart `core` (or the whole server).

## Usage
Other modules read the current player's account via `AccountService.getAccountId(source)`.
