pub mod eip1193;
pub mod eip6963;

use js_sys::Reflect;
use leptos::*;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};
use web_sys::window;

fn main() {
    console_error_panic_hook::set_once();

    let (count, set_count) = create_signal(0);

    let window = window().expect("no global `window` exists");

    let (provider, set_provider) = create_signal(None);

    let has_provider = move || provider().is_some();

    let announce_provider_callback = Closure::wrap(Box::new(move |event: web_sys::CustomEvent| {
        let detail = event.detail();

        // TODO: use serde to do this?
        let info = Reflect::get(&detail, &JsValue::from_str("info")).expect("no info");

        let info: eip6963::EIP6963ProviderInfo =
            serde_wasm_bindgen::from_value(info).expect("invalid info");

        logging::log!("{:?}", info);

        let provider = Reflect::get(&detail, &JsValue::from_str("provider")).unwrap();

        let provider = eip1193::EIP1193Provider::try_from(provider).unwrap();

        logging::log!("{:?}", provider);

        // TODO: make some calls in the background?

        set_provider(Some(provider));
    }) as Box<dyn FnMut(_)>);

    window
        .add_event_listener_with_callback(
            "eip6963:announceProvider",
            announce_provider_callback.as_ref().unchecked_ref(),
        )
        .expect("failed to add event listener");

    let request_provider_event = web_sys::CustomEvent::new("eip6963:requestProvider")
        .expect("failed to create custom event");

    window
        .dispatch_event(&request_provider_event)
        .expect("failed to dispatch event");

    // TODO:
    mount_to_body(move || {
        view! {
            <p>"Hello, world!"</p>
            <p>
                {move || {
                    if has_provider() {
                        return view! {
                            <button
                                on:click=move |_| {
                                    set_count.update(|n| *n += 1);
                                }
                            >
                                "Click me: "
                                // on stable, this is move || count.get();
                                {move || count()}
                            </button>
                        }.into_view();
                    } else {
                        return view! {
                            <p>
                                "Your browser is unsupported. No cryptocurrency wallet found. Please use"
                                <a href="https://www.coinbase.com/wallet">"Coinbase Wallet"</a>
                                "or"
                                <a href="https://frame.sh">"Frame"</a>
                            </p>
                        }.into_view();
                    }
                }}
            </p>
        }
    })
}
