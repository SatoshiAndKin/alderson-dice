use js_sys::{Function, Promise, Reflect};
use leptos::*;
use serde_json::{json, Value};
use wasm_bindgen::{closure::Closure, JsCast, JsValue};

// TODO: theres a bunch fields on here, but we don't need them yet
#[derive(Clone, Debug)]
pub struct EIP1193Provider {
    _inner: JsValue,
    // TODO: turn this into a function that we can call from rust
    _request: Function,
    _on: Function,
}

impl TryFrom<JsValue> for EIP1193Provider {
    type Error = JsValue;

    fn try_from(value: JsValue) -> Result<Self, Self::Error> {
        let request = Reflect::get(&value, &JsValue::from_str("request")).unwrap();

        if request.is_undefined() {
            return Err(JsValue::from_str("request is undefined"));
        }

        let request = request.dyn_into::<Function>()?;

        let on = Reflect::get(&value, &JsValue::from_str("on")).unwrap();

        let on = on.dyn_into::<Function>()?;

        let on_chain_changed = Closure::wrap(Box::new(move |args: JsValue| {
            let chain_id = args.as_string().expect("no chain id");
            logging::log!("chain_id: {:?}", chain_id);

            window()
                .location()
                .reload()
                .expect("failed to reload");
        }) as Box<dyn FnMut(JsValue)>);

        let on_chain_changed = on_chain_changed.into_js_value();

        on.call2(&value, &JsValue::from_str("chainChanged"), &on_chain_changed)?;

        Ok(Self {
            _inner: value,
            _request: request,
            _on: on,
        })
    }
}

impl EIP1193Provider {
    pub async fn request(&self, method: &str, params: Option<Value>) -> Result<JsValue, JsValue> {
        let args = json!({
            "method": method,
            "params": params,
        });

        let args = serde_wasm_bindgen::to_value(&args)?;

        let promise: Promise = self._request.call1(&self._inner, &args)?.unchecked_into();

        let result = wasm_bindgen_futures::JsFuture::from(promise).await?;

        Ok(result)
    }

    pub async fn chain_id(&self) -> Result<u64, JsValue> {
        let x = self.request("eth_chainId", None).await?;

        let x = x.as_string().unwrap();

        let x = u64::from_str_radix(&x[2..], 16).unwrap();

        Ok(x)
    }
}
