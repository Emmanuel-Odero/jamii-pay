use thiserror::Error;

#[derive(Debug, Error)]
pub enum WalletCoreError {
    #[error("invalid private key material")]
    InvalidKey,

    #[error("signing failed: {0}")]
    SigningFailed(String),

    #[error("invalid hex input: {0}")]
    InvalidHex(#[from] hex::FromHexError),
}
