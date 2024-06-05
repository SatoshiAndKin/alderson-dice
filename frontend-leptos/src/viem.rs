//! TODO: rust bindings for the viem module (https://github.com/ratchetdesigns/ts-bindgen ?)
//! TODO: component for the viem client https://viem.sh/docs/clients/transports/custom + https://viem.sh/docs/clients/transports/fallback
use std::collections::HashMap;

use js_sys::{Function, Object, Reflect};
use leptos::logging::log;
use leptos::WriteSignal;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};

use crate::createPublicClientForChain;

use super::createWalletClientForChain;

#[derive(Clone)]
pub struct ViemWallet {
    wallet_client: JsValue,
    public_client: JsValue,
}

impl ViemWallet {
    pub fn new(chain_id: String, eip1193_provider: JsValue) -> Self {
        let wallet_client = createWalletClientForChain(chain_id.clone(), eip1193_provider.clone());

        let public_client = createPublicClientForChain(chain_id, eip1193_provider);

        Self {
            wallet_client,
            public_client,
        }
    }

    /// TODO: return something that can be used to cancel the subscription
    pub fn watch_heads(&self, set_watch_heads: WriteSignal<Option<HashMap<String, JsValue>>>) {
        let closure = Closure::wrap(Box::new(move |block_header: JsValue| {
            let block_header = block_header
                .dyn_into::<Object>()
                .expect("header not an object");

            let block_header_keys = Reflect::own_keys(&block_header).expect("has keys");

            // TODO: i feel like there is a better way to turn an Object into a HashMap. probably using "entries"
            let mut block_header_map = HashMap::new();

            for key in block_header_keys.iter() {
                let value = Reflect::get(&block_header, &key).expect("getting key");

                let key = key.as_string().expect("key is not a string");

                block_header_map.insert(key, value);
            }

            log!("new block header: {:?}", block_header_map);

            set_watch_heads(Some(block_header_map));
        }) as Box<dyn FnMut(JsValue)>);

        let closure = closure.into_js_value();

        let arguments = Object::new();

        // TODO: use bindings from the typescript types
        Reflect::set(&arguments, &"onBlock".into(), &closure).expect("setting onBlock");

        let watch_blocks_fn = Reflect::get(&self.public_client, &"watchBlocks".into())
            .expect("getting watchBlocks")
            .dyn_into::<Function>()
            .expect("watchBlocks is not a function");

        watch_blocks_fn
            .call1(&self.wallet_client, &arguments.into())
            .expect("calling watchBlocks");
    }
}

impl std::fmt::Debug for ViemWallet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ViemWallet").finish()
    }
}
