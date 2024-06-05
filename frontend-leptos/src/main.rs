pub mod eip1193;
pub mod eip6963;
pub mod viem;

use js_sys::{BigInt, Reflect};
use leptos::{logging::log, *};
use wasm_bindgen::{closure::Closure, prelude::wasm_bindgen, JsCast, JsValue};
use web_sys::window;

use crate::viem::ViemWallet;

const ARBITRUM_CHAIN_ID: &str = "0xa4b1";

fn main() {
    console_error_panic_hook::set_once();

    mount_to_body(move || {
        view! {
            <App />
        }
    });
}

#[component]
fn App() -> impl IntoView {
    let window = window().expect("no global `window` exists");

    let x = hello();
    log!("{:?}", x);

    // TODO: subscribe to new heads here so people start seeing data immediately
    let defaultWallet = ViemWallet::new(ARBITRUM_CHAIN_ID.to_string(), None);

    // TODO: i think these should maybe be moved into their own components
    let (count, set_count) = create_signal(0);
    let (chain_id, set_chain_id) = create_signal("".to_string());
    let (accounts, set_accounts) = create_signal(Vec::new());
    let (provider, set_provider) = create_signal(None);
    let (wallet, set_wallet) = create_signal(Some(defaultWallet.clone()));
    let (latest_block_head, set_latest_block_header) = create_signal(None);

    defaultWallet.watch_heads(set_latest_block_header);

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

    // TODO: this action feels weird. we fire it from a button press but also from an event listener
    // TODO: move this all to using viem's helpers?
    let switch_chain: Action<(eip1193::EIP1193Provider, String, String), _> =
        create_action(move |input: &(eip1193::EIP1193Provider, String, String)| {
            let (provider, chain_id, desired_chain_id) = input.clone();

            async move {
                if !desired_chain_id.is_empty() {
                    if chain_id != desired_chain_id {
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
                        let wallet =
                            viem::ViemWallet::new(desired_chain_id, Some(provider.inner()));

                        set_wallet(Some(wallet.clone()));

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

                        wallet.watch_heads(set_latest_block_header);
                    }
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

        <button
            on:click=move |_| {
                set_count.update(|n| *n += 1);
                logging::log!("clicked");
            }
        >
            "Click me: "
            {count}
        </button>
        <hr />

        <Show
            when=move || { provider().is_some() }
            fallback=|| view! { <UnsupportedBrowser/> }
        >
            <article>
            {
                let provider: eip1193::EIP1193Provider = provider().unwrap();

                let dispatch_args = (provider.clone(), chain_id().clone(), ARBITRUM_CHAIN_ID.to_string());

                if chain_id() == ARBITRUM_CHAIN_ID {
                    // we call dispatch because we might start with the wallet already being connected. i don't love that
                    switch_chain.dispatch(dispatch_args);
                    view! {
                        <div>"chain_id: "{chain_id}</div>
                        // TODO: should this be a button that we can click to disconnect?
                        <div>"Successfully Connected to Arbitrum"</div>
                    }.into_view()
                } else {
                    view! {
                        <div>"wrong chain_id: "{chain_id}</div>

                        // a button that requests the arbitrum provider when clicked
                        <div>
                            <button
                                on:click=move |_| switch_chain.dispatch(dispatch_args.clone())
                            >
                                "Connect Your Wallet"
                            </button>
                        </div>
                        }.into_view()
                    }
                }
            </article>
        </Show>

        // // TODO: what should this be?
        // <Show
        //     when=move || { wallet().is_some() }
        // >
        //     <div>
        //         Able to query the chain
        //         // TODO: disconnect button
        //         // TODO: request account button
        //     </div>
        // </Show>

        <Show
            when=move || { !accounts().is_empty() }
            fallback=|| view! { <div>"No accounts"</div> }
        >
            <!-- "TODO: show accounts as an actual list" -->
            <!-- "TODO: disconnect button" -->
            <!-- "TODO: request account button" -->
            <article>
                "Accounts: "
                {accounts}
            </article>
        </Show>

        <Show
            when=move || { latest_block_head().is_some() }
        >
            <article>
                "Block Number: "
                {move || {
                    let latest_block_head = latest_block_head().expect("no block head");

                    let num = latest_block_head.get("number").expect("no block num").clone();

                    let num = num.dyn_into::<BigInt>().expect("num is bigint");

                    format!("{}", num.to_string(10).unwrap())
                }}
            </article>
        </Show>

        </main>
    }
}

#[component]
fn UnsupportedBrowser() -> impl IntoView {
    view! {
        <p>
            "Your browser is unsupported. No cryptocurrency wallet found. Please use the "
            <a href="https://www.coinbase.com/wallet">"Coinbase Wallet app"</a>
            " or the "
            <a href="https://frame.sh">"Frame browser extension"</a>.
        </p>
    }
}

#[wasm_bindgen(module = "/public-js/package.js")]
extern "C" {
    fn hello() -> String;

    fn createPublicClientForChain(chainId: String, eip1193_provider: JsValue) -> JsValue;

    fn createWalletClientForChain(chainId: String, eip1193Provider: JsValue) -> JsValue;
}
