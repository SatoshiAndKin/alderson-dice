use js_sys::{Function, Promise, Reflect};
use leptos::*;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};

// TODO: theres a bunch fields on here, but we don't need them yet
#[derive(Clone, Debug)]
pub struct EIP1193Provider {
    _inner: JsValue,
    // TODO: turn this into a function that we can call from rust
    _request: Function,
    _on: Function,
    _remove_listener: Function,
}

/*
interface ProviderMessage {
  readonly type: string;
  readonly data: unknown;
}

interface EthSubscription extends ProviderMessage {
  readonly type: 'eth_subscription';
  readonly data: {
    readonly subscription: string;
    readonly result: unknown;
  };
}

interface ProviderConnectInfo {
  readonly chainId: string;
}

interface ProviderRpcError extends Error {
  message: string;
  code: number;
  data?: unknown;
}
*/

impl EIP1193Provider {
    pub fn new(value: JsValue, set_chain_id: WriteSignal<String>) -> Result<Self, JsValue> {
        let request = Reflect::get(&value, &JsValue::from_str("request")).unwrap();

        if request.is_undefined() {
            return Err(JsValue::from_str("request is undefined"));
        }

        let request = request.dyn_into::<Function>()?;

        let on = Reflect::get(&value, &JsValue::from_str("on")).unwrap();

        let on = on.dyn_into::<Function>()?;

        // on_chain_changed
        // TODO: move this to a setter function
        let on_chain_changed = Closure::wrap(Box::new(move |chain_id: JsValue| {
            let chain_id = chain_id.as_string().expect("no chain id");
            logging::log!("chain_id: {:?}", chain_id);

            // TODO: with leptos, this is probably overkill. a signal should be enough
            // window().location().reload().expect("failed to reload");

            // TODO: convert the hex String into a u64?

            set_chain_id(chain_id);
        }) as Box<dyn FnMut(JsValue)>);

        let on_chain_changed = on_chain_changed.into_js_value();

        on.call2(
            &value,
            &JsValue::from_str("chainChanged"),
            &on_chain_changed,
        )?;

        // on_connect
        let on_connect = Closure::wrap(Box::new(move |connect_info: JsValue| {
            logging::log!("connect: {:?}", connect_info);
        }) as Box<dyn FnMut(JsValue)>);

        let on_connect = on_connect.into_js_value();

        on.call2(&value, &JsValue::from_str("connect"), &on_connect)?;

        // on_disconnect
        let on_disconnect = Closure::wrap(Box::new(move || {
            logging::log!("disconnect");
        }) as Box<dyn FnMut()>);

        let on_disconnect = on_disconnect.into_js_value();

        on.call2(&value, &JsValue::from_str("disconnect"), &on_disconnect)?;

        // on_message (for eth_subscribe)
        let on_message = Closure::wrap(Box::new(move |message: JsValue| {
            logging::log!("message: {:?}", message);

            // TODO: what do we do here? we need to track subscriptions and call the appropriate callbacks
        }) as Box<dyn FnMut(JsValue)>);

        let on_message = on_message.into_js_value();

        on.call2(&value, &JsValue::from_str("message"), &on_message)?;

        // on_accounts_changed
        let on_accounts_changed = Closure::wrap(Box::new(move |accounts: JsValue| {
            logging::log!("accounts: {:?}", accounts);
        }) as Box<dyn FnMut(JsValue)>);

        let on_accounts_changed = on_accounts_changed.into_js_value();

        on.call2(
            &value,
            &JsValue::from_str("accountsChanged"),
            &on_accounts_changed,
        )?;

        // remove listeners
        let remove_listener = Reflect::get(&value, &JsValue::from_str("removeListener")).unwrap();

        let remove_listener = remove_listener.dyn_into::<Function>()?;

        Ok(Self {
            _inner: value,
            _request: request,
            _on: on,
            _remove_listener: remove_listener,
        })
    }
}

impl EIP1193Provider {
    pub async fn request(
        &self,
        method: &str,
        params: Option<&JsValue>,
    ) -> Result<JsValue, JsValue> {
        let arg1 = js_sys::Object::new();

        js_sys::Reflect::set(
            &arg1,
            &JsValue::from_str("method"),
            &JsValue::from_str(method),
        )?;

        if let Some(params) = params {
            js_sys::Reflect::set(&arg1, &JsValue::from_str("params"), params)?;
        }

        // // TODO: need a debug_info
        // logging::info!("arg1: {:?}", arg1);

        let promise: Promise = self._request.call1(&self._inner, &arg1)?.unchecked_into();

        let result = wasm_bindgen_futures::JsFuture::from(promise).await?;

        Ok(result)
    }

    pub async fn chain_id(&self) -> Result<u64, JsValue> {
        let x = self.request("eth_chainId", None).await?;

        let x = x.as_string().unwrap();

        let x = u64::from_str_radix(&x[2..], 16).unwrap();

        Ok(x)
    }

    // TODO: what should the function signature on the callback be? should we use `terrors` instead of JsValue?
    // TODO: support unsubscribing
    pub async fn subscribe<F>(&self, action: &str, callback: F) -> Result<JsValue, JsValue>
    where
        F: Fn(()) -> Result<(), JsValue>,
    {
        let action = JsValue::from_str(action);

        let subscription_id = self.request("eth_subscribe", Some(&action)).await?;

        // hex str. we don't need to convert it though
        // let subscription_id = subscription_id.as_string().unwrap();

        logging::warn!(
            "save this subscription_id somewhere so that the on message callback can use it"
        );

        Ok(subscription_id)
    }
}
