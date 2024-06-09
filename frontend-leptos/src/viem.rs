//! TODO: rust bindings for the viem module (https://github.com/ratchetdesigns/ts-bindgen ?)
//! TODO: component for the viem client https://viem.sh/docs/clients/transports/custom + https://viem.sh/docs/clients/transports/fallback
//! TODO: <https://docs.walletconnect.com/web3modal/javascript/about>? use their modal instead of building all of it ourselves?
//! TODO: private wallet_client that sends to a protected relay instead of the user's node?
use std::collections::HashMap;

use js_sys::{Function, Object, Reflect};
use leptos::logging::log;
use leptos::WriteSignal;
use wasm_bindgen::{closure::Closure, JsCast, JsValue};

use crate::createPublicClientForChain;

use super::createWalletClientForChain;

#[derive(Clone)]
pub struct ViemWalletClient {
    inner: JsValue,
}

#[derive(Clone)]
pub struct ViemPublicClient {
    inner: JsValue,
}

impl ViemPublicClient {
    pub fn new(chain_id: String, eip1193_provider: Option<JsValue>) -> Self {
        let eip1193_provider = eip1193_provider.unwrap_or_else(JsValue::undefined);

        let public_client = createPublicClientForChain(chain_id, eip1193_provider);

        Self {
            inner: public_client,
        }
    }

    pub fn inner(&self) -> JsValue {
        self.inner.clone()
    }

    /// TODO: return something that can be used to cancel the subscription
    pub fn watch_heads(
        &self,
        set_watch_heads: WriteSignal<Option<HashMap<String, JsValue>>>,
        emit_missed: bool,
    ) -> Function {
        let inner = self.inner.clone();

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

            log!("new block header to {:?}: {:?}", inner, block_header_map);

            set_watch_heads(Some(block_header_map));
        }) as Box<dyn FnMut(JsValue)>);

        let closure = closure.into_js_value();

        let arguments = Object::new();

        // TODO: use bindings from the typescript types
        Reflect::set(&arguments, &"onBlock".into(), &closure).expect("setting onBlock");
        Reflect::set(&arguments, &"emitMissed".into(), &emit_missed.into())
            .expect("setting emitMissed");
        Reflect::set(&arguments, &"emitOnBegin".into(), &true.into()).expect("setting emitOnBegin");

        let watch_blocks_fn = Reflect::get(&self.inner, &"watchBlocks".into())
            .expect("getting watchBlocks")
            .dyn_into::<Function>()
            .expect("watchBlocks is not a function");

        watch_blocks_fn
            .call1(&self.inner, &arguments.into())
            .expect("calling watchBlocks")
            .dyn_into::<Function>()
            .expect("watchBlocks did not return a function")
    }
}

impl ViemWalletClient {
    /// TODO: eventually this can
    pub fn new(chain_id: String, eip1193_provider: JsValue) -> Self {
        let wallet_client = createWalletClientForChain(chain_id, eip1193_provider);

        Self {
            inner: wallet_client,
        }
    }

    pub fn inner(&self) -> JsValue {
        self.inner.clone()
    }
}

impl std::fmt::Debug for ViemPublicClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ViemPublicClient").finish()
    }
}

impl std::fmt::Debug for ViemWalletClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ViemWalletClient").finish()
    }
}

/// TODO: use automatically generated bindings instead
///
/// In general, contract instance methods follow the following format:
///
/// // function
/// contract.(estimateGas|read|simulate|write).(functionName)(args, options)
///
/// // event
/// contract.(createEventFilter|getEvents|watchEvent).(eventName)(args, options)
pub struct ReadOnlyContract {
    inner: JsValue,

    read_obj: Object,
    create_event_filter_obj: Object,
    estimate_gas_obj: Object,
    get_events_obj: Object,
    simulate_obj: Object,
    watch_event_obj: Object,
}

impl std::fmt::Debug for ReadOnlyContract {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ReadOnlyContract").finish_non_exhaustive()
    }
}

pub struct ReadAndWriteContract {
    contract: ReadOnlyContract,

    write_obj: Object,
}

impl std::fmt::Debug for ReadAndWriteContract {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ReadAndWriteContract")
            .finish_non_exhaustive()
    }
}

impl ReadOnlyContract {
    pub fn new(inner: JsValue) -> Self {
        // TODO: do javascript checks to see if it has the correct public client type

        let read_obj = Reflect::get(&inner, &"read".into())
            .expect("getting read")
            .dyn_into::<Object>()
            .expect("read is not an object");

        let create_event_filter_obj = Reflect::get(&inner, &"createEventFilter".into())
            .expect("getting createEventFilter")
            .dyn_into::<Object>()
            .expect("createEventFilter is not a function");

        let estimate_gas_obj = Reflect::get(&inner, &"estimateGas".into())
            .expect("getting estimateGas")
            .dyn_into::<Object>()
            .expect("estimateGas is not a function");

        let get_events_obj = Reflect::get(&inner, &"getEvents".into())
            .expect("getting getEvents")
            .dyn_into::<Object>()
            .expect("getEvents is not a function");

        let simulate_obj = Reflect::get(&inner, &"simulate".into())
            .expect("getting simulate")
            .dyn_into::<Object>()
            .expect("simulate is not a function");

        let watch_event_obj = Reflect::get(&inner, &"watchEvent".into())
            .expect("getting watchEvent")
            .dyn_into::<Object>()
            .expect("watchEvent is not a function");

        Self {
            inner,
            read_obj,
            create_event_filter_obj,
            estimate_gas_obj,
            get_events_obj,
            simulate_obj,
            watch_event_obj,
        }
    }

    pub fn inner(&self) -> JsValue {
        self.inner.clone()
    }

    fn run(
        &self,
        obj: &Object,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        let f = Reflect::get(obj, &fn_name.into())
            .expect("getting function from obj")
            .dyn_into::<Function>()
            .expect("fn_name is not a function");

        f.call2(&self.inner, args, options)
    }

    pub fn read(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.read_obj, fn_name, args, options)
    }

    pub fn create_event_filter(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.create_event_filter_obj, fn_name, args, options)
    }

    pub fn estimate_gas(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.estimate_gas_obj, fn_name, args, options)
    }

    pub fn get_events(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.get_events_obj, fn_name, args, options)
    }

    pub fn simulate(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.simulate_obj, fn_name, args, options)
    }

    pub fn watch_event(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.run(&self.watch_event_obj, fn_name, args, options)
    }
}

impl ReadAndWriteContract {
    pub fn new(inner: JsValue) -> Self {
        // TODO: do javascript checks to see if it has the correct public client type

        let write_obj = Reflect::get(&inner, &"write".into())
            .expect("getting write")
            .dyn_into::<Object>()
            .expect("write is not an object");

        // both reader and writer have an estimate gas fn
        let estimate_gas_obj = Reflect::get(&inner, &"estimateGas".into())
            .expect("getting estimateGas")
            .dyn_into::<Object>()
            .expect("estimateGas is not a function");

        let mut inner = ReadOnlyContract::new(inner);

        inner.estimate_gas_obj = estimate_gas_obj;

        Self {
            contract: inner,
            write_obj,
        }
    }

    pub fn inner(&self) -> JsValue {
        self.contract.inner()
    }

    pub fn read(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.contract.read(fn_name, args, options)
    }

    pub fn create_event_filter(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        // TODO: how do we unsubscribe from this?
        self.contract.create_event_filter(fn_name, args, options)
    }

    pub fn estimate_gas(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.contract.estimate_gas(fn_name, args, options)
    }

    pub fn get_events(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        // TODO: change ok return value into an array of event logs
        self.contract.get_events(fn_name, args, options)
    }

    pub fn simulate(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.contract.simulate(fn_name, args, options)
    }

    pub fn watch_event(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        // TODO: change ok return value into an "unwatch" function
        self.contract.watch_event(fn_name, args, options)
    }

    pub fn write(
        &self,
        fn_name: &str,
        args: &JsValue,
        options: &JsValue,
    ) -> Result<JsValue, JsValue> {
        self.contract.run(&self.write_obj, fn_name, args, options)
    }
}
