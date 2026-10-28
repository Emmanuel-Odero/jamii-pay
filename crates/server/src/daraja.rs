//! Safaricom Daraja API client — both directions of M-Pesa money
//! movement: STK Push (the "receive by prompting the other person's
//! phone" flow, [`DarajaConfig`]/[`stk_push`]) and B2C (the "pay out to a
//! real M-Pesa number" flow Cash-out uses, [`DarajaB2cConfig`]/
//! [`b2c_payment_request`]). Credentials are read from env vars, never
//! hardcoded — see each config's `from_env` for the exact names required,
//! `routes/mpesa.rs` for how STK Push's calls are used together, and
//! `routes/send_to_mpesa.rs` for B2C's.
//!
//! **Setup required before STK Push does anything real:**
//! 1. Daraja app credentials (consumer key/secret, the paybill/till
//!    shortcode, and the Lipa Na M-Pesa passkey) from
//!    developer.safaricom.co.ke, placed in this project's `.env`
//!    (never committed, never pasted into chat).
//! 2. A **publicly reachable HTTPS** callback URL. Safaricom's servers
//!    call `DARAJA_CALLBACK_URL` directly over the internet — they can
//!    never reach a LAN address like this dev server's
//!    `Ochiengs-MacBook-Pro.local`. For local testing, tunnel port 8081
//!    with `ngrok http 8081` and set `DARAJA_CALLBACK_URL` to the
//!    `https://*.ngrok-free.app/mpesa/callback` URL ngrok prints — it
//!    changes every time you restart ngrok on the free tier, so this
//!    has to be updated (and the server restarted) each session.
//!
//! **Additional setup for B2C (Cash-out)** — a separate Daraja app from
//! the STK Push one, since B2C needs its own shortcode/initiator
//! credentials:
//! 1. A B2C-enabled Daraja app (developer.safaricom.co.ke) — gives you
//!    the B2C shortcode, initiator name, and initiator password.
//! 2. Safaricom's public certificate for the environment you're using
//!    (sandbox vs production have different certs — both published at
//!    github.com/safaricom/mpesa-daraja-api-postman-collection), reduced
//!    to a plain PEM public key once via
//!    `openssl x509 -in SandboxCertificate.cer -pubkey -noout > pubkey.pem`.
//! 3. The same ngrok tunnel as STK Push works for the B2C result/timeout
//!    URLs too (it exposes the whole port, not just one path) — set
//!    `DARAJA_B2C_RESULT_URL`/`DARAJA_B2C_TIMEOUT_URL` to
//!    `https://*.ngrok-free.app/mpesa/b2c/{result,timeout}`.

use anyhow::{anyhow, Context, Result};
use base64::Engine;
use chrono::Utc;
use rsa::pkcs8::DecodePublicKey;
use rsa::{Pkcs1v15Encrypt, RsaPublicKey};
use serde::{Deserialize, Serialize};

#[derive(Clone)]
pub struct DarajaConfig {
    pub consumer_key: String,
    pub consumer_secret: String,
    /// The paybill/till number STK Push debits into.
    pub shortcode: String,
    pub passkey: String,
    /// Where Safaricom POSTs the result — must be public HTTPS, see the
    /// module doc comment.
    pub callback_url: String,
    /// `https://sandbox.safaricom.co.ke` or `https://api.safaricom.co.ke`.
    pub base_url: String,
}

impl DarajaConfig {
    /// `None` when any required env var is missing — callers treat this
    /// as "M-Pesa receive isn't configured yet" rather than a hard
    /// startup failure, since the rest of the app works fine without it.
    pub fn from_env() -> Option<Self> {
        Some(Self {
            consumer_key: std::env::var("DARAJA_CONSUMER_KEY").ok()?,
            consumer_secret: std::env::var("DARAJA_CONSUMER_SECRET").ok()?,
            shortcode: std::env::var("DARAJA_SHORTCODE").ok()?,
            passkey: std::env::var("DARAJA_PASSKEY").ok()?,
            callback_url: std::env::var("DARAJA_CALLBACK_URL").ok()?,
            base_url: std::env::var("DARAJA_BASE_URL").unwrap_or_else(|_| "https://sandbox.safaricom.co.ke".to_string()),
        })
    }
}

/// Config for the *outbound* direction — B2C ("Business to Customer"),
/// used by Cash-out to actually pay a real M-Pesa number instead of just
/// debiting the wallet and pretending. Separate from [`DarajaConfig`]
/// because B2C needs its own app on developer.safaricom.co.ke (a
/// different shortcode than the STK Push one, an initiator name/password,
/// and Safaricom's public certificate) — `consumer_key`/`consumer_secret`
/// are shared, everything else isn't.
#[derive(Clone)]
pub struct DarajaB2cConfig {
    pub consumer_key: String,
    pub consumer_secret: String,
    pub base_url: String,
    /// The B2C-enabled shortcode payments are debited from on Safaricom's
    /// side (their own float account) — not necessarily the same
    /// shortcode STK Push credits into.
    pub shortcode: String,
    /// The Daraja app's API operator username (set up alongside the app
    /// on the portal), NOT a phone number or the shortcode itself.
    pub initiator_name: String,
    /// The initiator's plaintext operator password — encrypted with
    /// Safaricom's public key per-request (see [`security_credential`]),
    /// never sent or logged as-is.
    pub initiator_password: String,
    /// PEM-encoded RSA public key (`-----BEGIN PUBLIC KEY-----...`),
    /// extracted from Safaricom's published certificate. Get it once via:
    /// `openssl x509 -in SandboxCertificate.cer -pubkey -noout > pubkey.pem`
    /// (production has its own, separate certificate — same command,
    /// different `.cer` file). Safaricom publishes both at
    /// github.com/safaricom/mpesa-daraja-api-postman-collection or from
    /// the Daraja portal's B2C documentation.
    pub public_key_pem: String,
    pub result_url: String,
    pub queue_timeout_url: String,
}

impl DarajaB2cConfig {
    /// `None` when any required env var is missing — callers treat this
    /// as "M-Pesa disbursement isn't configured yet" the same way
    /// [`DarajaConfig::from_env`] does for the receive direction.
    /// `DARAJA_B2C_PUBLIC_KEY_PATH` points at the PEM file described on
    /// [`DarajaB2cConfig::public_key_pem`] — read from disk rather than
    /// inline in `.env` so multi-line PEM content doesn't fight `.env`
    /// quoting/escaping.
    pub fn from_env() -> Option<Self> {
        let public_key_path = std::env::var("DARAJA_B2C_PUBLIC_KEY_PATH").ok()?;
        let public_key_pem = std::fs::read_to_string(&public_key_path).ok()?;
        Some(Self {
            consumer_key: std::env::var("DARAJA_CONSUMER_KEY").ok()?,
            consumer_secret: std::env::var("DARAJA_CONSUMER_SECRET").ok()?,
            base_url: std::env::var("DARAJA_BASE_URL").unwrap_or_else(|_| "https://sandbox.safaricom.co.ke".to_string()),
            shortcode: std::env::var("DARAJA_B2C_SHORTCODE").ok()?,
            initiator_name: std::env::var("DARAJA_B2C_INITIATOR_NAME").ok()?,
            initiator_password: std::env::var("DARAJA_B2C_INITIATOR_PASSWORD").ok()?,
            public_key_pem,
            result_url: std::env::var("DARAJA_B2C_RESULT_URL").ok()?,
            queue_timeout_url: std::env::var("DARAJA_B2C_TIMEOUT_URL").ok()?,
        })
    }

    /// Reuses [`DarajaConfig`]'s OAuth (same app-level credentials as STK
    /// Push, just a different API family) so `get_access_token` doesn't
    /// need duplicating.
    fn as_oauth_config(&self) -> DarajaConfig {
        DarajaConfig {
            consumer_key: self.consumer_key.clone(),
            consumer_secret: self.consumer_secret.clone(),
            shortcode: self.shortcode.clone(),
            passkey: String::new(),
            callback_url: String::new(),
            base_url: self.base_url.clone(),
        }
    }
}

/// Encrypts [`DarajaB2cConfig::initiator_password`] with Safaricom's
/// public key — Daraja never sees the plaintext password, only this
/// per-request ciphertext (`SecurityCredential`). PKCS#1 v1.5 padding is
/// what Safaricom's own API expects (not OAEP) — see the B2C API
/// reference on developer.safaricom.co.ke.
fn security_credential(config: &DarajaB2cConfig) -> Result<String> {
    let public_key = RsaPublicKey::from_public_key_pem(&config.public_key_pem)
        .context("parsing DARAJA_B2C_PUBLIC_KEY_PATH as a PEM public key")?;
    let mut rng = rand::thread_rng();
    let encrypted = public_key
        .encrypt(&mut rng, Pkcs1v15Encrypt, config.initiator_password.as_bytes())
        .context("encrypting the B2C initiator password")?;
    Ok(base64::engine::general_purpose::STANDARD.encode(encrypted))
}

#[derive(Deserialize)]
struct AccessTokenResponse {
    access_token: String,
}

/// `pub(crate)` — `routes/send_to_mpesa.rs` reuses this same OAuth call
/// for B2C/B2B (Safaricom's app-level credentials are shared across all
/// of STK Push, B2C, and B2B; only the security credential differs).
pub(crate) async fn get_access_token(config: &DarajaConfig) -> Result<String> {
    let client = reqwest::Client::new();
    let res = client
        .get(format!("{}/oauth/v1/generate?grant_type=client_credentials", config.base_url))
        .basic_auth(&config.consumer_key, Some(&config.consumer_secret))
        .send()
        .await
        .context("calling Daraja OAuth endpoint")?;

    if !res.status().is_success() {
        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        return Err(anyhow!("Daraja OAuth failed ({status}): {body}"));
    }

    Ok(res.json::<AccessTokenResponse>().await.context("parsing Daraja OAuth response")?.access_token)
}

#[derive(Serialize)]
struct StkPushRequest {
    #[serde(rename = "BusinessShortCode")]
    business_short_code: String,
    #[serde(rename = "Password")]
    password: String,
    #[serde(rename = "Timestamp")]
    timestamp: String,
    #[serde(rename = "TransactionType")]
    transaction_type: &'static str,
    #[serde(rename = "Amount")]
    amount: i64,
    #[serde(rename = "PartyA")]
    party_a: String,
    #[serde(rename = "PartyB")]
    party_b: String,
    #[serde(rename = "PhoneNumber")]
    phone_number: String,
    #[serde(rename = "CallBackURL")]
    call_back_url: String,
    #[serde(rename = "AccountReference")]
    account_reference: String,
    #[serde(rename = "TransactionDesc")]
    transaction_desc: String,
}

pub struct StkPushResult {
    pub checkout_request_id: String,
    pub merchant_request_id: String,
}

/// Prompts `phone` (format `2547XXXXXXXX`, no `+`) to pay `amount_kes`
/// (whole shillings, no decimals — Daraja rejects fractional amounts)
/// into this app's shortcode. Returns immediately with tracking ids;
/// the actual result arrives later at `DarajaConfig::callback_url` (see
/// `routes/mpesa.rs::stk_callback`).
pub async fn stk_push(config: &DarajaConfig, phone: &str, amount_kes: i64, account_reference: &str) -> Result<StkPushResult> {
    let access_token = get_access_token(config).await?;

    let timestamp = Utc::now().format("%Y%m%d%H%M%S").to_string();
    let password = base64::engine::general_purpose::STANDARD.encode(format!("{}{}{}", config.shortcode, config.passkey, timestamp));

    let req = StkPushRequest {
        business_short_code: config.shortcode.clone(),
        password,
        timestamp,
        transaction_type: "CustomerPayBillOnline",
        amount: amount_kes,
        party_a: phone.to_string(),
        party_b: config.shortcode.clone(),
        phone_number: phone.to_string(),
        call_back_url: config.callback_url.clone(),
        account_reference: account_reference.to_string(),
        transaction_desc: "JamiiPay top-up".to_string(),
    };

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/mpesa/stkpush/v1/processrequest", config.base_url))
        .bearer_auth(access_token)
        .json(&req)
        .send()
        .await
        .context("calling Daraja STK Push endpoint")?;

    if !res.status().is_success() {
        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        return Err(anyhow!("Daraja STK Push failed ({status}): {body}"));
    }

    #[derive(Deserialize)]
    struct Response {
        #[serde(rename = "CheckoutRequestID")]
        checkout_request_id: String,
        #[serde(rename = "MerchantRequestID")]
        merchant_request_id: String,
    }
    let body: Response = res.json().await.context("parsing Daraja STK Push response")?;
    Ok(StkPushResult { checkout_request_id: body.checkout_request_id, merchant_request_id: body.merchant_request_id })
}

/// Safaricom's callback body shape — see Daraja's STK Push Result
/// Payload documentation. `CallbackMetadata` is only present on success
/// (`ResultCode == 0`).
#[derive(Deserialize)]
pub struct StkCallbackBody {
    #[serde(rename = "Body")]
    pub body: StkCallbackInner,
}

#[derive(Deserialize)]
pub struct StkCallbackInner {
    #[serde(rename = "stkCallback")]
    pub stk_callback: StkCallback,
}

#[derive(Deserialize)]
pub struct StkCallback {
    #[serde(rename = "MerchantRequestID")]
    pub merchant_request_id: String,
    #[serde(rename = "CheckoutRequestID")]
    pub checkout_request_id: String,
    #[serde(rename = "ResultCode")]
    pub result_code: i64,
    #[serde(rename = "ResultDesc")]
    pub result_desc: String,
    #[serde(rename = "CallbackMetadata")]
    pub callback_metadata: Option<CallbackMetadata>,
}

#[derive(Deserialize)]
pub struct CallbackMetadata {
    #[serde(rename = "Item")]
    pub item: Vec<CallbackItem>,
}

#[derive(Deserialize)]
pub struct CallbackItem {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "Value")]
    pub value: Option<serde_json::Value>,
}

impl StkCallback {
    /// Pulls `MpesaReceiptNumber` out of `CallbackMetadata.Item` — the
    /// one field `routes/mpesa.rs` actually needs to record beyond the
    /// amount it already knows from the `mpesa_deposits` row it created
    /// at initiate-time.
    pub fn mpesa_receipt(&self) -> Option<String> {
        self.callback_metadata
            .as_ref()?
            .item
            .iter()
            .find(|i| i.name == "MpesaReceiptNumber")
            .and_then(|i| i.value.as_ref())
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    }
}

#[derive(Serialize)]
struct B2cRequest {
    #[serde(rename = "InitiatorName")]
    initiator_name: String,
    #[serde(rename = "SecurityCredential")]
    security_credential: String,
    #[serde(rename = "CommandID")]
    command_id: &'static str,
    #[serde(rename = "Amount")]
    amount: i64,
    #[serde(rename = "PartyA")]
    party_a: String,
    #[serde(rename = "PartyB")]
    party_b: String,
    #[serde(rename = "Remarks")]
    remarks: String,
    #[serde(rename = "QueueTimeOutURL")]
    queue_timeout_url: String,
    #[serde(rename = "ResultURL")]
    result_url: String,
    #[serde(rename = "Occasion")]
    occasion: String,
}

pub struct B2cResult {
    pub conversation_id: String,
    pub originator_conversation_id: String,
}

/// Pays `amount_kes` (whole shillings) out to `phone` (format
/// `2547XXXXXXXX`, no `+`) — the real disbursement Cash-out debits the
/// wallet for. `CommandID: BusinessPayment` is the general-purpose B2C
/// command (as opposed to `SalaryPayment`/`PromotionPayment`, which carry
/// different tax/reporting treatment on Safaricom's side and don't apply
/// here). Returns immediately with tracking ids; the actual result
/// arrives later at `DarajaB2cConfig::result_url` (see
/// `routes/send_to_mpesa.rs::b2c_result`) — a successful response here
/// only means Safaricom *accepted the request*, not that money has
/// actually moved yet.
pub async fn b2c_payment_request(config: &DarajaB2cConfig, phone: &str, amount_kes: i64, remarks: &str) -> Result<B2cResult> {
    let access_token = get_access_token(&config.as_oauth_config()).await?;
    let credential = security_credential(config)?;

    let req = B2cRequest {
        initiator_name: config.initiator_name.clone(),
        security_credential: credential,
        command_id: "BusinessPayment",
        amount: amount_kes,
        party_a: config.shortcode.clone(),
        party_b: phone.to_string(),
        remarks: remarks.to_string(),
        queue_timeout_url: config.queue_timeout_url.clone(),
        result_url: config.result_url.clone(),
        occasion: "Cash out".to_string(),
    };

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{}/mpesa/b2c/v1/paymentrequest", config.base_url))
        .bearer_auth(access_token)
        .json(&req)
        .send()
        .await
        .context("calling Daraja B2C endpoint")?;

    if !res.status().is_success() {
        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        return Err(anyhow!("Daraja B2C request failed ({status}): {body}"));
    }

    #[derive(Deserialize)]
    struct Response {
        #[serde(rename = "ConversationID")]
        conversation_id: String,
        #[serde(rename = "OriginatorConversationID")]
        originator_conversation_id: String,
    }
    let body: Response = res.json().await.context("parsing Daraja B2C response")?;
    Ok(B2cResult { conversation_id: body.conversation_id, originator_conversation_id: body.originator_conversation_id })
}

/// Safaricom's B2C result/timeout callback body shape — see the B2C API's
/// "Result Parameters" documentation. Unlike STK Push's flat
/// `CallbackMetadata`, B2C nests everything under `Result` and gives
/// each parameter a `Key`/`Value` pair with no fixed schema, so
/// [`B2cCallbackResult::parameter`] does the same lookup-by-name
/// `stk_callback` does for `MpesaReceiptNumber`.
#[derive(Deserialize)]
pub struct B2cCallbackBody {
    #[serde(rename = "Result")]
    pub result: B2cCallbackResult,
}

#[derive(Deserialize)]
pub struct B2cCallbackResult {
    #[serde(rename = "ResultType")]
    pub result_type: i64,
    #[serde(rename = "ResultCode")]
    pub result_code: i64,
    #[serde(rename = "ResultDesc")]
    pub result_desc: String,
    #[serde(rename = "OriginatorConversationID")]
    pub originator_conversation_id: String,
    #[serde(rename = "ConversationID")]
    pub conversation_id: String,
    #[serde(rename = "TransactionID")]
    pub transaction_id: Option<String>,
    #[serde(rename = "ResultParameters")]
    pub result_parameters: Option<B2cResultParameters>,
}

#[derive(Deserialize)]
pub struct B2cResultParameters {
    #[serde(rename = "ResultParameter")]
    pub result_parameter: Vec<CallbackItem>,
}

impl B2cCallbackResult {
    /// Looks up a named field in `ResultParameters` — e.g.
    /// `"TransactionReceipt"` for the M-Pesa receipt number, or
    /// `"ReceiverPartyPublicName"` for the recipient's registered name.
    pub fn parameter(&self, name: &str) -> Option<String> {
        self.result_parameters
            .as_ref()?
            .result_parameter
            .iter()
            .find(|i| i.name == name)
            .and_then(|i| i.value.as_ref())
            .map(|v| match v {
                serde_json::Value::String(s) => s.clone(),
                other => other.to_string(),
            })
    }
}
