pub mod eip1193;
pub mod eip6963;

use js_sys::Reflect;
use leptos::*;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};
use web_sys::window;

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

    let (provider, set_provider) = create_signal(None);
    let (count, set_count) = create_signal(0);
    let (chain_id, set_chain_id) = create_signal("".to_string());

    let announce_provider_callback = Closure::wrap(Box::new(move |event: web_sys::CustomEvent| {
        let detail = event.detail();

        // TODO: use serde to do this?
        let info = Reflect::get(&detail, &JsValue::from_str("info")).expect("no info");

        let info: eip6963::EIP6963ProviderInfo =
            serde_wasm_bindgen::from_value(info).expect("invalid info");

        logging::log!("{:?}", info);

        let provider = Reflect::get(&detail, &JsValue::from_str("provider")).unwrap();

        let provider = eip1193::EIP1193Provider::new(provider, set_chain_id).unwrap();

        logging::log!("{:?}", provider);

        // TODO: make some calls in the background?

        // TODO: this should be added to a list, rather than taking over
        set_provider(Some(provider));
    }) as Box<dyn FnMut(_)>);

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
        <h1>"Alderson Dice"</h1>

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

        <Show
            when=move || { provider().is_some() }
            fallback=|| view! { <UnsupportedBrowser/> }
        >
            <p>"Provider found!"</p>

            <button
                // define an event listener with on:
                on:click=move |_| {
                    let provider = provider().expect("no provider");

                    logging::log!("todo: check provider. if not arbitrum, ask to connect. {:?}", provider);

                    spawn_local(async move {
                        // TODO: this is wrong. we don't want to spawn local. we want to use <Suspense> and <ErrorBoundary>
                        let chain_id = provider.chain_id().await;

                        logging::log!("chain_id: {:?}", chain_id);
                    });
                }
            >
                // text nodes are wrapped in quotation marks
                "Connect to Arbitrum"
            </button>
        </Show>

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
