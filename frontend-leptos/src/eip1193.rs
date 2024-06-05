//! <https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1193.md>.

use js_sys::{Function, Promise, Reflect};
use leptos::*;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::RwLock;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};

// TODO: what should this type actually be?
type SubscriptionCallback = Box<dyn Fn(()) -> Result<(), JsValue>>;

// TODO: theres a bunch fields on here, but we don't need them yet
#[derive(Clone)]
pub struct EIP1193Provider {
    _inner: JsValue,
    // TODO: turn this into a function that we can call from rust
    _request: Function,
    _on: Function,
    _remove_listener: Function,

    // TODO: do we need an async lock here? is Rc okay or do we need Arc?
    subscriptions: Rc<RwLock<HashMap<String, SubscriptionCallback>>>,
}

impl PartialEq for EIP1193Provider {
    fn eq(&self, other: &Self) -> bool {
        self._inner == other._inner
    }
}

impl std::fmt::Debug for EIP1193Provider {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EIP1193Provider").finish_non_exhaustive()
    }
}

/*
TODO: write all these in rust:

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
    pub fn new(
        value: JsValue,
        set_chain_id: WriteSignal<String>,
        set_accounts: WriteSignal<Vec<String>>,
    ) -> Result<Self, JsValue> {
        let request = Reflect::get(&value, &"request".into()).unwrap();

        if request.is_undefined() {
            return Err("request is undefined".into());
        }

        let request = request.dyn_into::<Function>()?;

        let on = Reflect::get(&value, &"on".into()).unwrap();

        let on = on.dyn_into::<Function>()?;

        let subscriptions: Rc<RwLock<HashMap<String, SubscriptionCallback>>> = Default::default();

        // on_chain_changed
        // TODO: move this to a setter function
        let on_chain_changed = Closure::wrap(Box::new(move |chain_id: JsValue| {
            let chain_id = chain_id.as_string().expect("no chain id");
            logging::log!("chain_id: {:?}", chain_id);

            // the official docs recommend a reload on chain change. but leptos should keep everything in sync for us
            // window().location().reload().expect("failed to reload");

            set_chain_id(chain_id);
        }) as Box<dyn FnMut(JsValue)>);

        let on_chain_changed = on_chain_changed.into_js_value();

        on.call2(&value, &"chainChanged".into(), &on_chain_changed)?;

        // on_connect
        let on_connect = Closure::wrap(Box::new(move |connect_object: JsValue| {
            logging::log!("connect: {:?}", connect_object);

            // TODO: JsValue(Object({"chainId":"0xa4b1"}))

            let chain_id = Reflect::get(&connect_object, &"chainId".into())
                .expect("no chain id")
                .as_string()
                .expect("no chain id");

            set_chain_id(chain_id);
        }) as Box<dyn FnMut(JsValue)>);

        let on_connect = on_connect.into_js_value();

        on.call2(&value, &"connect".into(), &on_connect)?;

        // on_disconnect
        let on_disconnect = Closure::wrap(Box::new(move || {
            logging::log!("disconnect");

            set_chain_id("".to_string());
        }) as Box<dyn FnMut()>);

        let on_disconnect = on_disconnect.into_js_value();

        on.call2(&value, &"disconnect".into(), &on_disconnect)?;

        // on_message (for eth_subscribe)
        let on_message = {
            let subscriptions = subscriptions.clone();

            Closure::wrap(Box::new(move |message: JsValue| {
                logging::log!("message: {:?}", message);

                // TODO: what do we do here? we need to track subscriptions and call the appropriate callbacks

                let data = Reflect::get(&message, &"data".into()).unwrap();

                let sub_id = Reflect::get(&data, &"subscription".into())
                    .unwrap()
                    .as_string()
                    .unwrap();

                let subscriptions = subscriptions.read().expect("unable to lock subscriptions");

                if let Some(sub) = subscriptions.get(&sub_id) {
                    sub(()).expect("failed to call subscription callback");
                } else {
                    logging::log!("no subscription found for id: {:?}", sub_id);
                }
            }) as Box<dyn FnMut(JsValue)>)
        };

        let on_message = on_message.into_js_value();

        on.call2(&value, &"message".into(), &on_message)?;

        // on_accounts_changed
        let on_accounts_changed = Closure::wrap(Box::new(move |accounts: JsValue| {
            logging::log!("accounts changed: {:?}", accounts);

            let accounts = accounts
                .dyn_into::<js_sys::Array>()
                .expect("Expected an array for accounts");

            // TODO: turn this into an Address object?
            let accounts = accounts
                .iter()
                .map(|x| x.as_string().expect("account is not a string"))
                .collect();

            set_accounts(accounts);
        }) as Box<dyn FnMut(JsValue)>);

        let on_accounts_changed = on_accounts_changed.into_js_value();

        on.call2(&value, &"accountsChanged".into(), &on_accounts_changed)?;

        // remove listeners
        let remove_listener = Reflect::get(&value, &"removeListener".into()).unwrap();

        let remove_listener = remove_listener.dyn_into::<Function>()?;

        Ok(Self {
            _inner: value,
            _request: request,
            _on: on,
            _remove_listener: remove_listener,
            subscriptions,
        })
    }

    pub fn inner(&self) -> JsValue {
        self._inner.clone()
    }
}

impl EIP1193Provider {
    /// TODO: for params, instead of JsValue, take things that impl Serialize
    pub async fn request(
        &self,
        method: &str,
        params: Option<&JsValue>,
    ) -> Result<JsValue, JsValue> {
        let arg1 = js_sys::Object::new();

        js_sys::Reflect::set(&arg1, &"method".into(), &method.into())?;

        if let Some(params) = params {
            js_sys::Reflect::set(&arg1, &"params".into(), params)?;
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
    pub async fn subscribe<F>(
        &self,
        action: &str,
        callback: SubscriptionCallback,
    ) -> Result<(), JsValue> {
        let action = action.into();

        // TODO: if we have an http connection, this just won't
        let subscription_id = self.request("eth_subscribe", Some(&action)).await?;

        // hex str. we don't need to convert it though
        let subscription_id = subscription_id.as_string().unwrap();

        // save the subscription id and callback
        // an "on message" callback is already subscribed
        let mut lock = self
            .subscriptions
            .write()
            .expect("unable to lock subscriptions");

        lock.insert(subscription_id, callback);

        Ok(())
    }
}
