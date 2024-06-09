pub mod eip1193;
pub mod eip6963;
pub mod viem;

use derive_more::From;
use js_sys::{BigInt, Reflect};
use leptos::{logging::log, *};
use std::rc::Rc;
use std::sync::Mutex;
use viem::{ReadAndWriteContract, ReadOnlyContract, ViemPublicClient, ViemWalletClient};
use wasm_bindgen::{closure::Closure, prelude::wasm_bindgen, JsCast, JsValue};
use web_sys::window;

// TODO: make it easier to switch to dev chain. maybe only if theres a custom param in the url
const ARBITRUM_CHAIN_ID: &str = "0xa4b1";

fn main() {
    console_error_panic_hook::set_once();

    mount_to_body(move || {
        view! {
            <App />
        }
    });
}

#[derive(Debug, From)]
enum Contract {
    ReadOnly(ReadOnlyContract),
    ReadAndWrite(ReadAndWriteContract),
}

#[component]
fn App() -> impl IntoView {
    let window = window().expect("no global `window` exists");

    let x = hello();
    log!("{:?}", x);

    // give the users some data without any wallet connected
    let defaultPublicClient = ViemPublicClient::new(ARBITRUM_CHAIN_ID.to_string(), None);

    // TODO: i think these should maybe be moved into their own components
    let (count, set_count) = create_signal(0);
    let (chain_id, set_chain_id) = create_signal("".to_string());
    let (accounts, set_accounts) = create_signal(Vec::new());
    let (provider, set_provider) = create_signal(None);
    let (public_client, set_public_client) = create_signal(defaultPublicClient.clone());
    let (wallet_client, set_wallet_client) = create_signal::<Option<ViemWalletClient>>(None);
    let (latest_block_head, set_latest_block_header) = create_signal(None);

    let nft_contract = move || {
        let public_inner = public_client.with(|x| x.inner());

        if let Some(wallet) = wallet_client() {
            let nftContract = nftContract(public_inner, wallet.inner());

            // TODO: type specific to the game contract
            let nftContract = ReadAndWriteContract::new(nftContract);

            Contract::from(nftContract)
        } else {
            let nftContract = nftContract(public_inner, JsValue::undefined());

            let nftContract = ReadOnlyContract::new(nftContract);

            Contract::from(nftContract)
        }
    };

    let game_contract = move || {
        let public_inner = public_client.with(|x| x.inner());

        if let Some(wallet) = wallet_client() {
            // TODO: get the game address from the nft contract
            let gameContract = gameContract(public_inner, wallet.inner());

            let gameContract = ReadAndWriteContract::new(gameContract);

            // TODO: type specific to the game contract

            Contract::from(gameContract)
        } else {
            let gameContract = gameContract(public_inner, JsValue::undefined());

            let gameContract = ReadOnlyContract::new(gameContract);

            // TODO: type specific to the game contract

            Contract::from(gameContract)
        }
    };

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

        let provider =
            eip1193::EIP1193Provider::new(provider_value.clone(), set_chain_id, set_accounts)
                .unwrap();

        logging::log!("{:?}", provider);

        // TODO: make some calls in the background?

        // TODO: this should be added to a list, rather than taking over. then the user can pick which provider to use and we can make the wallet from that
        set_provider(Some(provider));
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

                    // TODO: DRY
                    {
                        let mut lock = block_subscription.lock().unwrap();

                        let (sub, context) = (&lock.0, &lock.1);

                        // TODO: this should just be a warning
                        let returned = sub.call0(context).expect("failed to unsubscribe");

                        log!("unsubscribed: {:?}", returned);

                        let sub = defaultPublicClient.watch_heads(set_latest_block_header, false);

                        *lock = (sub, defaultPublicClient.inner());
                    }

                    set_accounts.update(|x| x.clear());
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

                // TODO: what eip?
                // TODO: DRY. this same code is in the provider, but we do need it here too
                let accounts = provider
                    .request("eth_requestAccounts", None)
                    .await
                    .expect("failed to request accounts");

                let accounts = accounts
                    .dyn_into::<js_sys::Array>()
                    .expect("Expected an array for accounts");

                // TODO: turn this into an Address object?
                let accounts: Vec<_> = accounts
                    .iter()
                    .map(|x| x.as_string().expect("account is not a string"))
                    .collect();

                log!("requested accounts: {:?}", accounts);

                set_accounts(accounts);

                // TODO: save the wallet to localstorage so that we can automatically reconnect to it if we see it again. use the provider uuid or rdns?

                // TODO: we should probably have the bindings in rust instead of js... but then we need to figure out how to handle the provider
                // TODO: can we use ethers/alloy instead of viem?
            }

            chain_id
        }
    });

    let announce_provider_callback = announce_provider_callback.into_js_value();

    window
        .add_event_listener_with_callback(
            "eip6963:announceProvider",
            announce_provider_callback.unchecked_ref(),
        )
        .expect("failed to add event listener");

    let request_provider_event = web_sys::CustomEvent::new("eip6963:requestProvider")
        .expect("failed to create custom event");

    window
        .dispatch_event(&request_provider_event)
        .expect("failed to dispatch event");

    view! {
        <main class="container">
        <h1>"Alderson Dice"</h1>

        <article>
            <button
                on:click=move |_| {
                    set_count.update(|n| *n += 1);
                    logging::log!("clicked");
                }
            >
                "Click me: "
                {count}
            </button>
        </article>

        <Show
            when=move || { provider().is_some() }
            fallback=|| view! { <UnsupportedBrowser/> }
        >
            <article>
            {
                let provider: eip1193::EIP1193Provider = provider().unwrap();

                // TODO: don't call chain_id twice? use a resource? is that the right term?
                let disconnect_chain_args = (provider.clone(), chain_id().clone(), "".to_string());
                let switch_chain_args = (provider.clone(), chain_id().clone(), ARBITRUM_CHAIN_ID.to_string());

                if chain_id() == ARBITRUM_CHAIN_ID {
                    // we call dispatch because we might start with the wallet already being connected. i don't love this
                    switch_chain.dispatch(switch_chain_args);

                    view! {
                        <button
                            on:click=move |_| {
                                switch_chain.dispatch(disconnect_chain_args.clone())
                            }
                        >
                            "Disconnect Your Wallet"
                        </button>
                    }.into_view()
                } else {
                    view! {
                        // a button that requests the arbitrum provider when clicked
                        // TODO: this should open a modal that lists the user's injected wallets and lets them pick one
                        // TODO: should also let the user use other wallets like with walletconnect
                        <button
                            on:click=move |_| switch_chain.dispatch(switch_chain_args.clone())
                        >
                            "Connect Your Wallet to Arbitrum"
                        </button>
                    }.into_view()
                }
            }
            </article>
        </Show>

        // TODO: this should be a resource or maybe an action
        <article>
            {move || {
                if let Some(wallet) = wallet_client().as_ref() {
                    format!("{:?}", wallet)
                } else {
                    format!("{:?}", public_client())
                }
            }}
        </article>

        <Show
            when=move || { latest_block_head().is_some() }
        >
            <article>
                <div>
                    "Block Number: "
                    {move || {
                        // TODO: this should be a component or something like that
                        let latest_block_head = latest_block_head().expect("no block head");

                        let num = latest_block_head.get("number").expect("no block num").clone();

                        let num = num.dyn_into::<BigInt>().expect("num is bigint");

                        format!("{}", num.to_string(10).unwrap())
                    }}
                </div>
                <div>
                    "Block Age: "
                    // TODO: component for the block age
                    "???"
                </div>
                <div>
                    "Block Hash: "
                    // TODO: component for the block hash
                    "???"
                </div>
            </article>

            <article>
                "NFT Contract: "
                {move || {
                    let c = nft_contract();

                    // TODO: what should we print? the address?
                    format!("{:?}", c)
                }}
            </article>

            <article>
                "Game Contract: "
                {move || {
                    // TODO: what should we print? the address?
                    format!("{:?}", game_contract())
                }}
            </article>

            <article>
                "Total Dice: "
                "???"
            </article>

            <article>
                "This block's dice: "
                // TODO: component for the game's current bag according to the current block
                "???"
            </article>

            <article>
                "Other Account's Dice: "
                // TODO: component to prompt for accounts to watch
                "???"
            </article>
        </Show>

        <Show
            when=move || { !accounts().is_empty() }
        >
            // TODO: button to request accounts instead of only doing it on chain switch
            // this saves them having to hit "disconnect" when they want to add multiple accounts

            <article>
                // TODO: show accounts as an actual list so they can pick a primary one to manage
                "Your Accounts: "
                {accounts}
            </article>

            // TODO: component for seeing favorite dice
            // TODO: component for choosing favorite dice
            <article>
                "Favorite Dice: "
                "???"
            </article>

            <article>
            "Balances: "
            // TODO: component for balances
                "???"
            </article>

            // TODO: component for buying dice
            <article>
                "Buy Dice: "
                "???"
            </article>

            // TODO: component for selling dice
            <article>
                "Sell Dice: "
                "???"
            </article>

            // TODO: component for returning dice
            <article>
                "Return Dice: "
                "???"
            </article>

            // TODO: component for pending transactions
            <article>
                "Pending Transactions: "
                "???"
            </article>

            // TODO: component for transaction history
            <article>
                "Transaction History: "
                "???"
            </article>
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
            " or an extension like the "
            <a href="https://frame.sh">"Frame browser extension"</a>.
            "Support for wallet connect and other external wallets is in development."
        </article>
    }
}

#[wasm_bindgen(module = "/public-js/package.js")]
extern "C" {
    fn hello() -> String;

    fn createPublicClientForChain(chainId: String, eip1193_provider: JsValue) -> JsValue;

    fn createWalletClientForChain(chainId: String, eip1193Provider: JsValue) -> JsValue;

    fn nftContract(publicClient: JsValue, walletClient: JsValue) -> JsValue;

    fn gameContract(publicClient: JsValue, walletClient: JsValue) -> JsValue;
}
