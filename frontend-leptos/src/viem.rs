//! TODO: rust bindings for the viem module (https://github.com/ratchetdesigns/ts-bindgen ?)
//! TODO: component for the viem client https://viem.sh/docs/clients/transports/custom + https://viem.sh/docs/clients/transports/fallback
use wasm_bindgen::JsValue;

use super::createWalletClientForChain;

#[derive(Clone)]
pub struct ViemWallet {
    _inner: JsValue,
}

impl ViemWallet {
    pub fn new(chain_id: String, eip1193_provider: JsValue) -> Self {
        let inner = createWalletClientForChain(chain_id, eip1193_provider);

        Self { _inner: inner }
    }
}

impl std::fmt::Debug for ViemWallet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ViemWallet").finish()
    }
}
