pub mod eip1193;
pub mod eip6963;
pub mod viem;

use derive_more::From;
use js_sys::{Array, BigInt, Object, Reflect};
use leptos::{logging::log, *};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use std::{collections::HashMap, rc::Rc};
use viem::{ReadAndWriteContract, ReadOnlyContract, ViemPublicClient, ViemWalletClient};
use wasm_bindgen::{closure::Closure, prelude::wasm_bindgen, JsCast, JsValue};
use web_sys::window;

// TODO: make it easier to switch to dev chain. maybe only if theres a custom param in the url
const ARBITRUM_CHAIN_ID: &str = "0xa4b1";

// TODO: get this from the build artifacts
const NFT_ADDRESS: &str = "0xFFA4DB58Ad08525dFeB232858992047ECab26e95";

fn main() {
    console_error_panic_hook::set_once();

    mount_to_body(move || {
        view! { <App/> }
    });
}

#[derive(Clone, Debug, From, PartialEq)]
enum Contract {
    ReadOnly(ReadOnlyContract),
    ReadAndWrite(ReadAndWriteContract),
}

impl Contract {
    pub async fn read(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        match self {
            Contract::ReadOnly(contract) => contract.read(fn_name, args, options).await,
            Contract::ReadAndWrite(contract) => contract.read(fn_name, args, options).await,
        }
    }

    pub fn address(&self) -> Option<String> {
        let inner = self.inner_ref();

        Reflect::get(inner, &"address".into())
            .expect("failed to get address")
            .as_string()
    }

    pub fn inner(&self) -> JsValue {
        match self {
            Contract::ReadOnly(contract) => contract.inner.clone(),
            Contract::ReadAndWrite(contract) => contract.inner(),
        }
    }

    pub fn inner_ref(&self) -> &JsValue {
        match self {
            Contract::ReadOnly(contract) => &contract.inner,
            Contract::ReadAndWrite(contract) => contract.inner_ref(),
        }
    }

    // pub fn public_client(&self) -> JsValue {
    //     match self {
    //         Contract::ReadOnly(contract) => contract.public_client.clone(),
    //         Contract::ReadAndWrite(contract) => contract.public_client.clone(),
    //     }
    // }

    // pub fn wallet_client(&self) -> Option<JsValue> {
    //     match self {
    //         Contract::ReadOnly(_) => None,
    //         Contract::ReadAndWrite(contract) => Some(contract.wallet_client.clone()),
    //     }
    // }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
struct DiceColor {
    id: usize,
    name: String,
    symbol: String,
    pips: Vec<String>,
}

#[component]
fn App() -> impl IntoView {
    let the_window = window().expect("no global `window` exists");

    let x = hello();
    log!("{:?}", x);

    // give the users some data without any wallet connected
    let defaultPublicClient = ViemPublicClient::new(ARBITRUM_CHAIN_ID.to_string(), None);

    // TODO: i think these should maybe be moved into their own components
    let (count, set_count) = create_signal(0);

    let (all_providers, set_all_providers) = create_signal(Vec::new());

    // TODO: i want this to be a resource except for the fact that we call set_chain_id inside a callback
    // TODO: maybe that callback should be rewritten to instead call refetch on this? that doesn't seem right either
    let (selected_provider, set_selected_provider) =
        create_signal::<Option<eip1193::EIP1193Provider>>(None);

    let (chain_id, set_chain_id) = create_signal("".to_string());
    let (public_client, set_public_client) = create_signal(defaultPublicClient.clone());
    let (wallet_client, set_wallet_client) = create_signal::<Option<ViemWalletClient>>(None);

    let (latest_block_head, set_latest_block_header) =
        create_signal::<Option<HashMap<String, JsValue>>>(None);

    let latest_block_number = move || {
        if let Some(block) = latest_block_head() {
            if let Some(number) = block.get("number") {
                let number = number.dyn_ref::<BigInt>().expect("timestamp is bigint");

                let number = format!("{}", number.to_string(10).unwrap());

                Some(number)
            } else {
                None
            }
        } else {
            None
        }
    };

    let latest_block_timestamp = move || {
        if let Some(block) = latest_block_head() {
            if let Some(timestamp) = block.get("timestamp") {
                let timestamp = timestamp.dyn_ref::<BigInt>().expect("timestamp is bigint");

                let timestamp = format!("{}", timestamp.to_string(10).unwrap());

                Some(timestamp)
            } else {
                None
            }
        } else {
            None
        }
    };

    let latest_block_hash = move || {
        if let Some(block) = latest_block_head() {
            if let Some(x) = block.get("hash") {
                let x = x.as_string().expect("blockhash is not a string");
                Some(x)
            } else {
                log!("valid keys: {:?}", block.keys());
                None
            }
        } else {
            None
        }
    };

    let nft_contract = move || {
        let public_inner = public_client.with(|x| x.inner());

        let contract = if let Some(wallet) = wallet_client() {
            let wallet_inner = wallet.inner();

            let nftContract = nftContract(
                public_inner.clone(),
                wallet_inner.clone(),
                NFT_ADDRESS.to_string(),
            );

            // TODO: type specific to the game contract
            let nftContract = ReadAndWriteContract::new(nftContract);

            Contract::ReadAndWrite(nftContract)
        } else {
            let nftContract = nftContract(
                public_inner.clone(),
                JsValue::undefined(),
                NFT_ADDRESS.to_string(),
            );

            let nftContract = ReadOnlyContract::new(nftContract);

            Contract::ReadOnly(nftContract)
        };

        let the_window = window().expect("no window");

        Reflect::set(&the_window, &"nftContract".into(), &contract.inner())
            .expect("failed to set nft contract");

        contract
    };

    let nft_contract_address = move || {
        nft_contract()
            .address()
            .expect("this will always have an address")
    };

    let game_contract_address = create_resource(nft_contract, |nft_contract| async move {
        nft_contract
            .read("gameLogic", &JsValue::undefined(), &JsValue::undefined())
            .await
            .expect("failed to get game logic")
            .as_string()
            .expect("game logic is not a string")
    });

    let game_contract = move || {
        let public_inner = public_client.with(|x| x.inner());

        match (game_contract_address(), wallet_client()) {
            (Some(game_contract_address), Some(wallet_client)) => {
                let nftContract = gameContract(
                    public_inner.clone(),
                    wallet_client.inner(),
                    game_contract_address,
                );

                // TODO: type specific to the game contract
                let nftContract = ReadAndWriteContract::new(nftContract);

                Some(Contract::ReadAndWrite(nftContract))
            }
            (Some(game_contract_address), None) => {
                let nftContract = gameContract(
                    public_inner.clone(),
                    JsValue::undefined(),
                    game_contract_address,
                );

                let nftContract = ReadOnlyContract::new(nftContract);

                Some(Contract::ReadOnly(nftContract))
            }
            _ => None,
        }
    };

    let accounts: Resource<Option<ViemWalletClient>, Vec<String>> =
        create_resource(wallet_client, |wallet_client| async move {
            if let Some(wallet_client) = wallet_client {
                wallet_client
                    .request_addresses()
                    .await
                    .expect("request addresses failed")
            } else {
                vec![]
            }
        });

    // TODO: eventually emit_missed should be a user option
    // TODO: if another provider is chosen, this subscription should be ended
    let block_sub = defaultPublicClient.watch_heads(set_latest_block_header, false);

    let block_subscription = Rc::new(Mutex::new((block_sub, defaultPublicClient.inner())));

    let announce_provider_callback = Closure::wrap(Box::new(move |event: web_sys::CustomEvent| {
        let detail = event.detail();

        let info = Reflect::get(&detail, &"info".into()).expect("no info");

        let info: eip6963::EIP6963ProviderInfo =
            serde_wasm_bindgen::from_value(info).expect("invalid info");

        logging::log!("{:?}", info);

        let provider_value = Reflect::get(&detail, &"provider".into()).unwrap();

        let provider = eip1193::EIP1193Provider::new(provider_value).unwrap();

        logging::log!("{:?}", provider);

        set_all_providers.update(|x| {
            // TODO: this should probably get the whole eip6963 object
            // TODO: de-dupe?
            x.push(provider);

            match x.len() {
                0 => unimplemented!(),
                1 => set_selected_provider(x.first().cloned()),
                _ => {
                    log!(
                        "multiple providers are not supported yet. continuing to use the first one"
                    );
                }
            }
        });
    }) as Box<dyn FnMut(_)>);

    // TODO: this action feels wrong. we fire it from a button press but also from an event listener
    // TODO: i think most of the things in here should be moved to derived signals
    let switch_chain = create_action(move |input: &(eip1193::EIP1193Provider, String, String)| {
        let (provider, chain_id, desired_chain_id) = input.clone();
        let defaultPublicClient = defaultPublicClient.clone();
        let block_subscription = block_subscription.clone();

        async move {
            // TODO: there should maybe be a match here? otherwise i think this is just wrong overall and not how components/actions should work
            if desired_chain_id.is_empty() {
                if !chain_id.is_empty() {
                    // TODO: really not sure about this. it feels wrong. but this lets us disconnect the wallet
                    set_wallet_client(None);
                    set_public_client(defaultPublicClient.clone());

                    // this should be inside the Drop on WalletClient
                    {
                        let mut lock = block_subscription.lock().unwrap();

                        let (sub, context) = (&lock.0, &lock.1);

                        // TODO: this should just be a warning
                        let returned = sub.call0(context).expect("failed to unsubscribe");

                        log!("unsubscribed: {:?}", returned);

                        let sub = defaultPublicClient.watch_heads(set_latest_block_header, false);

                        *lock = (sub, defaultPublicClient.inner());
                    }

                    set_chain_id("".to_string());
                }
            } else if chain_id != desired_chain_id {
                // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1102.md>
                // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2255.md>
                // <https://eips.ethereum.org/EIPS/eip-3326>
                #[derive(serde::Serialize)]
                struct Params<'a> {
                    chainId: &'a str,
                }

                // TODO: convenience method for this
                let params = serde_wasm_bindgen::to_value(&[Params {
                    chainId: &desired_chain_id,
                }])
                .unwrap();

                // we don't actually need to do anything with this result because we have hooks for the chain id changing elsewhere
                let switched = provider
                    .request("wallet_switchEthereumChain", Some(&params))
                    .await
                    .expect("failed to switch chain");

                log!("switched: {:?}", switched);

                set_chain_id(desired_chain_id);
            } else {
                // TODO: this should maybe be a separate action tied to provider changing?
                let wallet =
                    viem::ViemWalletClient::new(desired_chain_id.clone(), provider.inner());

                let public = viem::ViemPublicClient::new(desired_chain_id, Some(provider.inner()));

                set_wallet_client(Some(wallet.clone()));
                set_public_client(public.clone());

                // TODO: DRY
                {
                    let mut lock = block_subscription.lock().unwrap();

                    let (sub, context) = (&lock.0, &lock.1);

                    let returned = sub.call0(context).expect("failed to unsubscribe");

                    log!("unsubscribed: {:?}", returned);

                    let sub = public.watch_heads(set_latest_block_header, false);

                    *lock = (sub, public.inner());
                }

                // TODO: save the wallet to localstorage so that we can automatically reconnect to it if we see it again. use the provider uuid or rdns?

                // TODO: we should probably have the bindings in rust instead of js... but then we need to figure out how to handle the provider
                // TODO: can we use ethers/alloy instead of viem?
            }

            chain_id
        }
    });

    // TODO: shame we don't have automatic types on this
    let total_dice = create_resource(
        move || (nft_contract(), latest_block_hash()),
        |(nft_contract, block_hash)| async move {
            // TODO: subscribe to logs here. not sure how to have that signal write to this

            // TODO: what option do we add to include this block number/hash in the query
            let total_dice = nft_contract
                .read("totalSupply", &JsValue::undefined(), &JsValue::undefined())
                .await
                .expect("failed to get total dice");

            let total_dice = total_dice
                .dyn_into::<BigInt>()
                .expect("total dice is not a bigint");

            let total_dice = total_dice.to_string(10).unwrap();

            format!("{}", total_dice)
        },
    );

    let dice_colors = create_resource(game_contract, |game_contract| async move {
        // TODO: do these concurrently
        let mut dice = Vec::<DiceColor>::new();

        // TODO: is there a better way to turn an array into the color?
        let die_info = game_contract?
            .read("allDice", &JsValue::undefined(), &JsValue::undefined())
            .await
            .expect("failed to get all dice")
            .dyn_into::<Array>()
            .expect("color is not an array");

        // TODO: wat? where are the pips?
        log!("die_info: {:?}", die_info);

        for (i, d) in die_info.into_iter().enumerate() {
            let d = d.dyn_into::<Object>().expect("d is not an object");

            let name = Reflect::get(&d, &"name".into())
                .expect("name is not present")
                .as_string()
                .expect("name should be a string");

            let symbol = Reflect::get(&d, &"symbol".into())
                .expect("symbol is not present")
                .as_string()
                .expect("symbol should be a string");

            // TODO: converting through f64? eww why
            let pips = Reflect::get(&d, &"pips".into())
                .expect("pips is not present")
                .dyn_into::<Array>()
                .expect("pips is not an array")
                .into_iter()
                .map(|x| x.as_f64().expect("pip is not a number").to_string())
                .collect::<Vec<_>>();

            let color = DiceColor {
                id: i,
                name,
                symbol,
                pips,
            };

            dice.push(color);
        }

        log!("dice: {:?}", dice);

        Some(dice)
    });

    // TODO: this is probably not the right way to pass dice_colors through. but calling it fails
    let current_bag = create_resource(
        move || (game_contract(), latest_block_number(), dice_colors()),
        |(game_contract, latest_block_number, dice_colors)| async move {
            match (game_contract, latest_block_number, dice_colors) {
                (Some(game_contract), Some(latest_block_number), Some(Some(dice_colors))) => {
                    let current_bag = game_contract
                        .read("currentBag", &JsValue::undefined(), &JsValue::undefined())
                        .await
                        .expect("failed to get current bag")
                        .dyn_into::<Array>()
                        .expect("current bag is not an array")
                        .into_iter()
                        .map(|x| {
                            // TODO: there has to be a better way
                            let color_id = x
                                .dyn_into::<BigInt>()
                                .expect("current bag item is not a BigInt")
                                .to_string(10)
                                .unwrap()
                                .as_string()
                                .expect("current bag bigint is not a string")
                                .parse::<usize>()
                                .expect("curent bag string is not a usize")
                                % dice_colors.len();

                            // TODO: get the dice_colors from the other resource

                            dice_colors[color_id].clone()
                        })
                        .collect::<Vec<_>>();

                    Some(current_bag)
                }
                _ => None,
            }
        },
    );

    let announce_provider_callback = announce_provider_callback.into_js_value();

    the_window
        .add_event_listener_with_callback(
            "eip6963:announceProvider",
            announce_provider_callback.unchecked_ref(),
        )
        .expect("failed to add event listener");

    let request_provider_event = web_sys::CustomEvent::new("eip6963:requestProvider")
        .expect("failed to create custom event");

    the_window
        .dispatch_event(&request_provider_event)
        .expect("failed to dispatch event");

    view! {
        <main class="container">
            <h1>"Alderson Dice"</h1>

            <article>
                <button on:click=move |_| {
                    set_count.update(|n| *n += 1);
                    logging::log!("clicked");
                }>

                    "Click me: " {count}
                </button>
            </article>

            <Show
                when=move || { selected_provider().is_some() }
                fallback=|| view! { <UnsupportedBrowser/> }
            >
                <article>

                    {
                        let provider: eip1193::EIP1193Provider = selected_provider().unwrap();
                        let disconnect_chain_args = (
                            provider.clone(),
                            chain_id().clone(),
                            "".to_string(),
                        );
                        let switch_chain_args = (
                            provider.clone(),
                            chain_id().clone(),
                            ARBITRUM_CHAIN_ID.to_string(),
                        );
                        if chain_id() == ARBITRUM_CHAIN_ID {
                            switch_chain.dispatch(switch_chain_args);
                            view! {
                                // we call dispatch because we might start with the wallet already being connected. i don't love this
                                // TODO: don't call chain_id twice? use a resource? is that the right term?

                                // TODO: dropdown to change the chain?

                                // we call dispatch because we might start with the wallet already being connected. i don't love this

                                <button on:click=move |_| {
                                    switch_chain.dispatch(disconnect_chain_args.clone())
                                }>

                                    "Disconnect Your Wallet"
                                </button>
                            }
                                .into_view()
                        } else {
                            view! {
                                // we call dispatch because we might start with the wallet already being connected. i don't love this
                                // TODO: don't call chain_id twice? use a resource? is that the right term?

                                // TODO: dropdown to change the chain?

                                // we call dispatch because we might start with the wallet already being connected. i don't love this

                                // we call dispatch because we might start with the wallet already being connected. i don't love this
                                // TODO: don't call chain_id twice? use a resource? is that the right term?

                                // TODO: dropdown to change the chain?

                                // we call dispatch because we might start with the wallet already being connected. i don't love this

                                // a button that requests the arbitrum provider and accounts when clicked
                                // TODO: this should open a modal that lists the user's injected wallets and lets them pick one
                                // TODO: should also let the user use other wallets like with walletconnect
                                // TODO: if the user has already clicked the button this session, dipatch now?
                                <button on:click=move |_| {
                                    switch_chain.dispatch(switch_chain_args.clone())
                                }>"Connect Your Wallet to Arbitrum"</button>
                            }
                                .into_view()
                        }
                    }

                </article>
            </Show>

            // TODO: this should be a resource or maybe an action
            <article>
                {move || {
                    if let Some(wallet) = wallet_client() {
                        format!("{:?}", wallet)
                    } else {
                        format!("{:?}", public_client())
                    }
                }}

            </article>

            <Show when=move || { latest_block_head().is_some() }>
                <article>
                    <div>"Block Number: " {latest_block_number}</div>
                    <div>
                        // TODO: component for the block age
                        "Block Timestamp: " {latest_block_timestamp}
                    </div>
                    <div>
                        // TODO: component for the block hash
                        "Block Hash: " {latest_block_hash}
                    </div>
                </article>

                <article>"NFT Contract: " {move || { format!("{} - {:?}", nft_contract_address(), nft_contract()) }}</article>

                <article>"Total Dice: " {total_dice}</article>

                <Show when=move || game_contract().is_some()>
                    <article>"Game Contract: " {move || { format!("{:?} - {:?}", game_contract_address().expect("game_contract is set so the address must be too"), game_contract()) }}</article>

                    // TODO: loading spinner

                    <article>"Dice Colors: " {move || format!("{:?}", dice_colors())}</article>

                // TODO: loading spinner
                // TODO: animation every change
                    <Show
                        when=move || { current_bag().map(|x| x.is_some()).unwrap_or(false) }
                        fallback=|| view! { <article>"Block's dice are loading..."</article> }
                    >
                        <article>
                            "This block's dice: "
                            // TODO: component for the game's current bag according to the current block

                            {
                                let current_bag = current_bag().unwrap().unwrap();
                                current_bag
                                    .into_iter()
                                    .map(|dice_color| {
                                        view! {
                                            // TODO: is the bag giving us a dice id? if so, then we need to turn that into a color
                                            // TODO: on-hover show the color name and pips
                                            // TODO: show the number rolled on top of each die
                                            {&dice_color.symbol}
                                            " "
                                        }
                                    })
                                    .collect_view()
                            }

                        </article>
                    </Show>

                    <article>
                        // TODO: component to prompt for accounts to watch
                        "Other Account's Dice: " "???"
                    </article>
                </Show>
            </Show>

            // TODO: use `with` here?
            <Show when=move || match accounts() {
                None => false,
                Some(x) => !x.is_empty(),
            }>
                // TODO: button to request accounts instead of only doing it on chain switch
                // this saves them having to hit "disconnect" when they want to add multiple accounts

                <article>
                    // TODO: show accounts as an actual list so they can pick a primary one to manage
                    "Your Accounts: " {accounts}
                </article>

                // TODO: component for seeing favorite dice
                // TODO: component for choosing favorite dice
                <article>"Favorite Dice: " "???"</article>

                <article>
                    // TODO: component for balances
                    "Balances: " "???"
                </article>

                // TODO: component for buying dice
                <article>"Buy Dice: " "???"</article>

                // TODO: component for selling dice
                <article>"Sell Dice: " "???"</article>

                // TODO: component for returning dice
                <article>"Return Dice: " "???"</article>

                // TODO: component for pending transactions
                <article>"Pending Transactions: " "???"</article>

                // TODO: component for transaction history
                <article>"Transaction History: " "???"</article>
            </Show>

        </main>
    }
}

#[component]
fn UnsupportedBrowser() -> impl IntoView {
    view! {
        <article>
            "Your browser is missing a cryptocurrency wallet extension. Please use the "
            <a href="https://www.coinbase.com/wallet">"Coinbase Wallet app"</a>
            " or an extension like the " <a href="https://frame.sh">"Frame browser extension"</a> .
            "Support for wallet connect and other external wallets is in development."
        </article>
    }
}

#[wasm_bindgen(module = "/public-js/package.js")]
extern "C" {
    fn hello() -> String;

    fn createPublicClientForChain(chainId: String, eip1193_provider: JsValue) -> JsValue;

    fn createWalletClientForChain(chainId: String, eip1193Provider: JsValue) -> JsValue;

    fn nftContract(publicClient: JsValue, walletClient: JsValue, address: String) -> JsValue;

    fn gameContract(publicClient: JsValue, walletClient: JsValue, address: String) -> JsValue;
}
