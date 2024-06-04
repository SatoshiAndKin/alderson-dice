pub mod eip1193;
pub mod eip6963;

use js_sys::Reflect;
use leptos::{logging::log, *};
use std::collections::HashMap;
use wasm_bindgen::{closure::Closure, prelude::wasm_bindgen, JsCast};
use web_sys::window;

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

    let (provider, set_provider) = create_signal(None);
    let (count, set_count) = create_signal(0);
    let (chain_id, set_chain_id) = create_signal("".to_string());

    let announce_provider_callback = Closure::wrap(Box::new(move |event: web_sys::CustomEvent| {
        let detail = event.detail();

        // TODO: use serde to do this?
        let info = Reflect::get(&detail, &"info".into()).expect("no info");

        let info: eip6963::EIP6963ProviderInfo =
            serde_wasm_bindgen::from_value(info).expect("invalid info");

        logging::log!("{:?}", info);

        let provider = Reflect::get(&detail, &"provider".into()).unwrap();

        let provider = eip1193::EIP1193Provider::new(provider, set_chain_id).unwrap();

        logging::log!("{:?}", provider);

        // TODO: make some calls in the background?

        // TODO: this should be added to a list, rather than taking over
        set_provider(Some(provider));
    }) as Box<dyn FnMut(_)>);

    let (desired_chain, set_desired_chain) = create_signal("");
    let desired_chain_resource = create_resource(
        move || (provider(), chain_id(), desired_chain()),
        move |(provider, chain_id, desired_chain_id)| async move {
            if let Some(provider) = provider {
                if desired_chain_id != "" && chain_id != desired_chain_id {
                    // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1102.md>
                    // <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-2255.md>
                    // <https://eips.ethereum.org/EIPS/eip-3326>
                    #[derive(serde::Serialize)]
                    struct Params {
                        chainId: &'static str,
                    }

                    // TODO: should this be a json string, or should it be a js object?
                    let params = serde_wasm_bindgen::to_value(&[Params {
                        chainId: desired_chain_id,
                    }])
                    .unwrap();

                    // TODO: how do we handle async things here?
                    // <https://docs.rs/leptos/latest/leptos/fn.create_resource.html>
                    let f = provider.request("wallet_switchEthereumChain", Some(&params));

                    // // i don't like this, but i want this to only run once and not keep forcing the chain back and it does that
                    // set_desired_chain("");

                    // we don't actually need to do anything with this result because we have hooks for the chain id changing elsewhere
                    f.await.unwrap();
                }
            }

            chain_id
        },
    );

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
        <div class="container">
        <h1>"Alderson Dice"</h1>

        <div>
            <button
                // define an event listener with on:
                on:click=move |_| {
                    set_count.update(|n| *n += 1);

                    logging::log!("clicked");
                }
            >
                // text nodes are wrapped in quotation marks
                "Click me: "
                // blocks can include Rust code
                {count}
            </button>
        </div>

        <Show
            when=move || { provider().is_some() }
            fallback=|| view! { <UnsupportedBrowser/> }
        >
            <div>
            {
                let chain_id = chain_id();

                if chain_id == ARBITRUM_CHAIN_ID {
                    view! {
                        "Connected to Arbitrum"
                    }.into_view()
                } else {
                    view! {
                        // a button that requests the arbitrum provider when clicked
                        <button
                            // define an event listener with on:
                            on:click=move |_| {

                                // connected to some other chain (or we got here quickly and the wallet hasn't responded yet)
                                logging::log!("wrong chain_id: {:?}", chain_id);

                                set_desired_chain(ARBITRUM_CHAIN_ID);

                            }
                            >
                            "Connect to Arbitrum"
                            </button>
                        }.into_view()
                    }
                }
                </div>
                </Show>

        // TODO: what do we do with this? we need to show it somewhere
        <Show
            when=move || { !chain_id().is_empty() }
        >
            <div>"chain_id: "{chain_id}</div>
        </Show>

        </div>
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
}
