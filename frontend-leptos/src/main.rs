pub mod eip1193;
pub mod eip6963;

use js_sys::Reflect;
use leptos::{logging::log, *};
use wasm_bindgen::{closure::Closure, prelude::wasm_bindgen, JsCast, JsValue};
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

    let client = createPublicArbitrumClient();
    log!("client: {:?}", client);

    Reflect::set(&window, &JsValue::from_str("client"), &client).unwrap();

    // log!("publicClient: {:?}", publicClient);

    // let response = hello();
    // log!("hello response: {:?}", response);

    let (count, set_count) = create_signal(0);
    let (chain_id, set_chain_id) = create_signal("".to_string());

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
    fn createPublicArbitrumClient() -> JsValue;

    // TODO: how do we use this?
    fn createPublicClient(options: JsValue) -> JsValue;

    fn webSocket() -> JsValue;

    fn http() -> JsValue;

    #[wasm_bindgen(js_name = arbitrum)]
    static ARBITRUM: JsValue;
}
