module musenft_addr::main {
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_framework::object::ExtendRef;
    use aptos_std::string_utils::{to_string};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use std::error;
    use std::option;
    use std::signer::address_of;
    use std::signer;
    use std::string::{Self, String};

    /// musesong not available
    const ENOT_AVAILABLE: u64 = 1;
    /// name length exceeded limit
    const ENAME_LIMIT: u64 = 2;
    /// user already has musesong
    // const EUSER_ALREADY_HAS_MUSESONG: u64 = 3;

    // maximum health points: 5 hearts * 2 HP/heart = 10 HP
    const ENERGY_UPPER_BOUND: u64 = 10;
    const TITLE_UPPER_BOUND: u64 = 40;

    struct MuseSong has key {
        id: String,
        title: String,
        prompt: String,
        image_url: String,
        audio_url: String,
        tags: String,
        points: u64,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,
    }

    #[event]
    struct MintMuseSongEvent has drop, store {
        token_name: String,
        id: String,
        title: String,
        audio_url: String
    }

    // We need a contract signer as the creator of the musesong collection and musesong token
    // Otherwise we need admin to sign whenever a new musesong token is minted which is inconvenient
    struct ObjectController has key {
        // This is the extend_ref of the app object, not the extend_ref of collection object or token object
        // app object is the creator and owner of musesong collection object
        // app object is also the creator of all musesong token (NFT) objects
        // but owner of each token object is musesong owner (i.e. user who mints musesong)
        app_extend_ref: ExtendRef,
    }

    const APP_OBJECT_SEED: vector<u8> = b"MUSESONG";
    const MUSESONG_COLLECTION_NAME: vector<u8> = b"MUSESONG Collection";
    const MUSESONG_COLLECTION_DESCRIPTION: vector<u8> = b"MUSESONG Collection Description";
    const MUSESONG_COLLECTION_URI: vector<u8> = b"https://www.reviewmingle.xyz/_next/image?url=%2Fandroid-chrome-192x192.png&w=48&q=75";

    // This function is only called once when the module is published for the first time.
    fun init_module(account: &signer) {
        let constructor_ref = object::create_named_object(
            account,
            APP_OBJECT_SEED,
        );
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let app_signer = &object::generate_signer(&constructor_ref);

        move_to(app_signer, ObjectController {
            app_extend_ref: extend_ref,
        });

        create_musesong_collection(app_signer);
    }

    // ================================= Helper Functions ================================= //

    fun get_app_signer_addr(): address {
        object::create_object_address(&@musenft_addr, APP_OBJECT_SEED)
    }

    fun get_app_signer(): signer acquires ObjectController {
        object::generate_signer_for_extending(&borrow_global<ObjectController>(get_app_signer_addr()).app_extend_ref)
    }

    // Create the collection that will hold all the musesongs
    fun create_musesong_collection(creator: &signer) {
        let description = string::utf8(MUSESONG_COLLECTION_DESCRIPTION);
        let name = string::utf8(MUSESONG_COLLECTION_NAME);
        let uri = string::utf8(MUSESONG_COLLECTION_URI);

        collection::create_unlimited_collection(
            creator,
            description,
            name,
            option::none(),
            uri,
        );
    }

    // ================================= Entry Functions ================================= //

    // Create an Musesong token object
    public entry fun create_musesong(
        user: &signer,
        id: String,
        title: String,
        prompt: String,
        image_url: String,
        audio_url: String,
        tags: String
    ) acquires ObjectController {
        assert!(string::length(&title) <= TITLE_UPPER_BOUND, error::invalid_argument(ENAME_LIMIT));

        let uri = string::utf8(MUSESONG_COLLECTION_URI);
        let description = string::utf8(MUSESONG_COLLECTION_DESCRIPTION);
        let user_addr = address_of(user);
        let token_name = id;
        
        // assert!(!has_musesong(token_name), error::already_exists(EUSER_ALREADY_HAS_MUSESONG));

        let constructor_ref = token::create_named_token(
            &get_app_signer(),
            string::utf8(MUSESONG_COLLECTION_NAME),
            description,
            token_name,
            option::none(),
            uri,
        );

        let token_signer = object::generate_signer(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);        

        // initialize/set default MuseSong struct values
        let musesong = MuseSong {
            id,
            title,
            prompt,
            image_url,
            audio_url,
            tags,
            points: ENERGY_UPPER_BOUND,
            mutator_ref,
            burn_ref,
        };

        move_to(&token_signer, musesong);

        // Emit event for minting MuseSong token
        event::emit<MintMuseSongEvent>(
            MintMuseSongEvent {
                token_name,
                id,
                title,
                audio_url
            },
        );

        object::transfer_with_ref(object::generate_linear_transfer_ref(&transfer_ref), address_of(user));
    }

    // Feeds MuseSong to increase its energy points
    public entry fun feed(owner: &signer, points: u64) acquires MuseSong {
        let owner_addr = signer::address_of(owner);
        assert!(has_musesong(owner_addr), error::unavailable(ENOT_AVAILABLE));
        let token_address = get_musesong_address(owner_addr);
        let musesong = borrow_global_mut<MuseSong>(token_address);

        musesong.points = if (musesong.points + points > ENERGY_UPPER_BOUND) {
            ENERGY_UPPER_BOUND
        } else {
            musesong.points + points
        };
    }

    // Plays with MuseSong to consume its points
    public entry fun play(owner: &signer, points: u64) acquires MuseSong {
        let owner_addr = signer::address_of(owner);
        assert!(has_musesong(owner_addr), error::unavailable(ENOT_AVAILABLE));
        let token_address = get_musesong_address(owner_addr);
        let musesong = borrow_global_mut<MuseSong>(token_address);

        musesong.points = if (musesong.points < points) {
            0
        } else {
            musesong.points - points
        };
    }

    // ================================= View Functions ================================== //

    // Get reference to MuseSong token object (CAN'T modify the reference)
    #[view]
    public fun get_musesong_address(creator_addr: address): (address) {
        let collection = string::utf8(MUSESONG_COLLECTION_NAME);
        let token_name = to_string(&creator_addr);
        let creator_addr = get_app_signer_addr();
        let token_address = token::create_token_address(
            &creator_addr,
            &collection,
            &token_name,
        );

        token_address
    }

    // Get collection address (also known as collection ID) of musesong collection
    // Collection itself is an object, that's why it has an address
    #[view]
    public fun get_musesong_collection_address(): (address) {
        let collection_name = string::utf8(MUSESONG_COLLECTION_NAME);
        let creator_addr = get_app_signer_addr();
        collection::create_collection_address(&creator_addr, &collection_name)
    }

    // Returns true if this address owns an MuseSong
    #[view]
    public fun has_musesong(owner_addr: address): (bool) {
        let token_address = get_musesong_address(owner_addr);

        exists<MuseSong>(token_address)
    }

    // Returns all fields for this MuseSong (if found)
    #[view]
    public fun get_musesong(
        owner_addr: address
    ): (String, String, String, String, String, String, u64) acquires MuseSong {
        // if this address doesn't have an MuseSong, throw error
        assert!(has_musesong(owner_addr), error::unavailable(ENOT_AVAILABLE));

        let token_address = get_musesong_address(owner_addr);
        let musesong = borrow_global<MuseSong>(token_address);

        // view function can only return primitive types.
        (musesong.id, musesong.title, musesong.prompt, musesong.image_url, musesong.audio_url, musesong.tags, musesong.points)
    }

     // Returns all fields for this MuseSong (if found)
    #[view]
    public fun get_musesong_with_token_address(
        token_address: address
    ): (String, String, String, String, String, String, u64) acquires MuseSong {
        // if this address doesn't have an MuseSong, throw error
        // assert!(has_musesong(token_address), error::unavailable(ENOT_AVAILABLE));

        let musesong = borrow_global<MuseSong>(token_address);

        // view function can only return primitive types.
        (musesong.id, musesong.title, musesong.prompt, musesong.image_url, musesong.audio_url, musesong.tags, musesong.points)
    }


    // ================================= Unit Tests ================================== //

    // Setup testing environment
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    #[test_only]
    use std::string::utf8;

    #[test_only]
    fun setup_test(aptos: &signer, account: &signer, creator: &signer) {
        // create a fake account (only for testing purposes)
        create_account_for_test(signer::address_of(creator));
        create_account_for_test(signer::address_of(account));

        timestamp::set_time_has_started_for_testing(aptos);
        init_module(account);
    }

    // Test creating an Musesong
    #[test(aptos = @0x1, account = @musenft_addr, creator = @0x123)]
    fun test_create_musesong(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_musesong(creator, utf8(b"fc102432-9f06-44a5-841e-773baacec045"), utf8(b"After the Thunder"), utf8(b"A popular heavy metal song about war, sung by a deep-voiced male singer, slowly and melodiously. The lyrics depict the sorrow of people after the war."), utf8(b"https://cdn2.suno.ai/image_fc102432-9f06-44a5-841e-773baacec045.jpeg"), utf8(b"https://cdn1.suno.ai/fc102432-9f06-44a5-841e-773baacec045.mp3"), utf8(b"heavy metal slow melodic"));

        let has_musesong = has_musesong(signer::address_of(creator));
        assert!(has_musesong, 1);
    }

    // Test getting an Musesong, when user has not minted
    #[test(aptos = @0x1, account = @musenft_addr, creator = @0x123)]
    #[expected_failure(abort_code = 851969, location = musenft_addr::main)]
    fun test_get_musesong_without_creation(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires MuseSong {
        setup_test(aptos, account, creator);

        // get musesong without creating it
        get_musesong(signer::address_of(creator));
    }

    // Test getting an MuseSong, when user has not minted
    #[test(aptos = @0x1, account = @musenft_addr, creator = @0x123)]
    #[expected_failure(abort_code = 524291, location = musenft_addr::main)]
    fun test_create_musesong_twice(
        aptos: &signer,
        account: &signer,
        creator: &signer
    ) acquires ObjectController {
        setup_test(aptos, account, creator);

        create_musesong(creator, utf8(b"fc102432-9f06-44a5-841e-773baacec045"), utf8(b"After the Thunder"), utf8(b"A popular heavy metal song about war, sung by a deep-voiced male singer, slowly and melodiously. The lyrics depict the sorrow of people after the war."), utf8(b"https://cdn2.suno.ai/image_fc102432-9f06-44a5-841e-773baacec045.jpeg"), utf8(b"https://cdn1.suno.ai/fc102432-9f06-44a5-841e-773baacec045.mp3"));
        create_musesong(creator, utf8(b"fc102432-9f06-44a5-841e-773baacec045"), utf8(b"After the Thunder"), utf8(b"A popular heavy metal song about war, sung by a deep-voiced male singer, slowly and melodiously. The lyrics depict the sorrow of people after the war."), utf8(b"https://cdn2.suno.ai/image_fc102432-9f06-44a5-841e-773baacec045.jpeg"), utf8(b"https://cdn1.suno.ai/fc102432-9f06-44a5-841e-773baacec045.mp3"));
    }
}
