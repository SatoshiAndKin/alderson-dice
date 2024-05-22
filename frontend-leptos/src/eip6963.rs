use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct EIP6963ProviderInfo {
    uuid: String,
    name: String,
    icon: String,
    rdns: String,
}
