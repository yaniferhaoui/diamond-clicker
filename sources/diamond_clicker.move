module diamond_clicker::game {
    use std::signer;
    use std::vector;

    use aptos_framework::timestamp;

    #[test_only]
    use aptos_framework::account;

    /*
    Errors
    DO NOT EDIT
    */
    const ERROR_GAME_STORE_DOES_NOT_EXIST: u64 = 0;
    const ERROR_UPGRADE_DOES_NOT_EXIST: u64 = 1;
    const ERROR_NOT_ENOUGH_DIAMONDS_TO_UPGRADE: u64 = 2;

    /*
    Const
    DO NOT EDIT
    */
    const POWERUP_NAMES: vector<vector<u8>> = vector[b"Bruh", b"Aptomingos", b"Aptos Monkeys"];
    // cost, dpm (diamonds per minute)
    const POWERUP_VALUES: vector<vector<u64>> = vector[
        vector[5, 5],
        vector[25, 30],
        vector[250, 350],
    ];

    /*
    Structs
    DO NOT EDIT
    */
    struct Upgrade has key, store, copy {
        name: vector<u8>,
        amount: u64
    }

    struct GameStore has key {
        diamonds: u64,
        upgrades: vector<Upgrade>,
        last_claimed_timestamp_seconds: u64,
    }

    /*
    Functions
    */
   public fun initialize_game(account: &signer) {
        let new_game_store = GameStore {
            diamonds: 1,
            upgrades: vector<Upgrade>[],
            last_claimed_timestamp_seconds: 0,
        };
        move_to(account, new_game_store);
    }

    public entry fun click(account: &signer) acquires GameStore {
        let sender_address = signer::address_of(account);
        
        if (exists<GameStore>(sender_address)) {
            let game_store = borrow_global_mut<GameStore>(sender_address);
            game_store.diamonds = game_store.diamonds + 1;
        } else {
            initialize_game(account);
        }
    }

    fun get_unclaimed_diamonds(game_store: &GameStore, current_timestamp_seconds: u64): u64 {
        let unclaimed_diamonds = 0;
        let minutes_elapsed = (current_timestamp_seconds - game_store.last_claimed_timestamp_seconds) / 60;

        let index = 0;
        let upgrades_len = vector::length(&game_store.upgrades);

        while (index < upgrades_len) {
            let upgrade = vector::borrow(&game_store.upgrades, index);
            let powerup_index = index;
            let powerup_length = vector::length(&POWERUP_VALUES);
            if (powerup_index < powerup_length) {
                let powerup = vector::borrow(&POWERUP_VALUES, powerup_index);
                let dpm = vector::borrow(powerup, 1);
                unclaimed_diamonds = unclaimed_diamonds + (*dpm * upgrade.amount * minutes_elapsed);
            };
            index = index + 1;
        };

        return unclaimed_diamonds
    }

    fun claim(account_address: address) acquires GameStore {
        assert!(exists<GameStore>(account_address), ERROR_GAME_STORE_DOES_NOT_EXIST);

        let current_timestamp_seconds = timestamp::now_seconds();
        let game_store = borrow_global_mut<GameStore>(account_address);
        let unclaimed_diamonds = get_unclaimed_diamonds(game_store, current_timestamp_seconds);

        game_store.diamonds = game_store.diamonds + unclaimed_diamonds;
        game_store.last_claimed_timestamp_seconds = current_timestamp_seconds;
    }

    public entry fun upgrade(account: &signer, upgrade_index: u64, upgrade_amount: u64) acquires GameStore {

        let powerup_names_length = vector::length(&POWERUP_NAMES);
        assert!(upgrade_index < powerup_names_length, ERROR_UPGRADE_DOES_NOT_EXIST);
        
        let sender_address = signer::address_of(account);
        claim(sender_address);

        let game_store = borrow_global_mut<GameStore>(sender_address);

        if (!exists<GameStore>(sender_address)) {
            initialize_game(account);
            game_store = borrow_global_mut<GameStore>(sender_address);
        };

        let powerup = vector::borrow(&POWERUP_VALUES, upgrade_index);
        let cost = vector::borrow(powerup, 0);
        let total_upgrade_cost = *cost * upgrade_amount;
        assert!(game_store.diamonds >= total_upgrade_cost, ERROR_NOT_ENOUGH_DIAMONDS_TO_UPGRADE);

        let index = 0;
        let upgrades_len = vector::length(&game_store.upgrades);
        let upgrade_existed = false;

        while (index < upgrades_len) {
            let upgrade = vector::borrow_mut(&mut game_store.upgrades, index);
            let powerup = vector::borrow(&POWERUP_NAMES, upgrade_index);
            if (upgrade.name == *powerup) {
                upgrade.amount = upgrade.amount + upgrade_amount;
                upgrade_existed = true;
                break
            };
            index = index + 1;
        };

        if (!upgrade_existed) {
            let powerup = vector::borrow(&POWERUP_NAMES, upgrade_index);
            let new_upgrade = Upgrade {
                name: *powerup,
                amount: upgrade_amount,
            };

            vector::push_back(&mut game_store.upgrades, new_upgrade);
        };

        game_store.diamonds = game_store.diamonds - total_upgrade_cost;
    }

    #[view]
    public fun get_diamonds(account_address: address): u64 acquires GameStore {
        let current_game_store = borrow_global<GameStore>(account_address);
        let unclaimed_diamonds = get_unclaimed_diamonds(current_game_store, timestamp::now_seconds());
        return current_game_store.diamonds + unclaimed_diamonds
    }

    #[view]
    public fun get_diamonds_per_minute(account_address: address): u64 acquires GameStore {
        let current_game_store = borrow_global<GameStore>(account_address);
        let diamonds_per_minute: u64 = 0;

        let upgrade_index = 0;
        let upgrades_len = vector::length(&current_game_store.upgrades);

        while (upgrade_index < upgrades_len) {
            let upgrade = vector::borrow(&current_game_store.upgrades, upgrade_index);
            let powerup = vector::borrow(&POWERUP_VALUES, upgrade_index);
            let dpm = vector::borrow(powerup, 1);
            diamonds_per_minute = diamonds_per_minute + (*dpm) * upgrade.amount;
            upgrade_index = upgrade_index + 1;
        };

        return diamonds_per_minute
    }

    #[view]
    public fun get_powerups(account_address: address): vector<Upgrade> acquires GameStore {
        let current_game_store = borrow_global<GameStore>(account_address);
        return current_game_store.upgrades
    }

    /*
    Tests
    DO NOT EDIT
    */
    inline fun test_click_loop(signer: &signer, amount: u64) acquires GameStore {
        let i = 0;
        while (amount > i) {
            click(signer);
            i = i + 1;
        }
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_click_without_initialize_game(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);
        let test_one_address = signer::address_of(test_one);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 1, 0);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_click_with_initialize_game(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);
        let test_one_address = signer::address_of(test_one);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 1, 0);

        click(test_one);

        let current_game_store = borrow_global<GameStore>(test_one_address);

        assert!(current_game_store.diamonds == 2, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    #[expected_failure(abort_code = 0, location = diamond_clicker::game)]
    fun test_upgrade_does_not_exist(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    #[expected_failure(abort_code = 2, location = diamond_clicker::game)]
    fun test_upgrade_does_not_have_enough_diamonds(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        click(test_one);
        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_one(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 5);
        upgrade(test_one, 0, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_two(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 25);

        upgrade(test_one, 1, 1);
    }

    #[test(aptos_framework = @0x1, account = @0xCAFE, test_one = @0x12)]
    fun test_upgrade_three(
        aptos_framework: &signer,
        account: &signer,
        test_one: &signer,
    ) acquires GameStore {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let aptos_framework_address = signer::address_of(aptos_framework);
        let account_address = signer::address_of(account);

        account::create_account_for_test(aptos_framework_address);
        account::create_account_for_test(account_address);

        test_click_loop(test_one, 250);

        upgrade(test_one, 2, 1);
    }
}