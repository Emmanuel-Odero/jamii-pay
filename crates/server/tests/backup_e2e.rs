//! End-to-end proof of the v2 split-backup loop against a running server:
//! generate → split → OPAQUE register → escrow S2 → OPAQUE login → combine.
//! This is the exact sequence the Flutter app runs (same `wallet_core`
//! functions, same HTTP endpoints), minus the QR render in the middle.
//!
//! Requires a live server + migrated DB:
//! `API_E2E_BASE=http://localhost:8081 cargo test --package server --test backup_e2e`
//!
//! Ignored by default (`cargo test --workspace` skips it) — it needs
//! infrastructure, not just code.

use serde_json::Value;
use sha2::{Digest, Sha256};
use wallet_core::opaque::{
    client_login_finish, client_login_start, client_register_finish, client_register_start,
};

fn base() -> String {
    std::env::var("API_E2E_BASE").unwrap_or_else(|_| "http://localhost:8081".to_string())
}

fn sha256_hex(pin: &str) -> String {
    hex::encode(Sha256::digest(pin.as_bytes()))
}

async fn post(client: &reqwest::Client, path: &str, body: Value) -> (u16, Value) {
    let res = client
        .post(format!("{}{}", base(), path))
        .json(&body)
        .send()
        .await
        .expect("server reachable");
    let status = res.status().as_u16();
    let json: Value = res.json().await.unwrap_or(Value::Null);
    (status, json)
}

#[tokio::test]
#[ignore]
async fn v2_backup_export_then_opaque_restore_roundtrip() {
    let client = reqwest::Client::new();
    let handle = format!("e2e{:08x}", rand::random::<u32>());
    let wallet_pin = "482920";
    let key_pin = "correct horse 42";

    // 1. Create a wallet.
    let key = wallet_core::api::generate_wallet();
    let (status, created) = post(
        &client,
        "/wallets",
        serde_json::json!({
            "evm_address": key.address_hex,
            "handle_base": handle,
            "guardians": ["device", "printed_code", "institutional"],
            "pin_hash": sha256_hex(wallet_pin),
        }),
    )
    .await;
    assert_eq!(status, 200, "create wallet: {created}");
    let wallet_id = created["id"].as_str().unwrap().to_string();

    // 2. Split + OPAQUE-register + escrow (the export flow).
    let split_raw = wallet_core::api::create_split_backup(
        key.private_key_hex.clone(),
        key.address_hex.clone(),
        key_pin.to_string(),
    )
    .expect("split");
    let split: Value = serde_json::from_str(&split_raw).unwrap();
    let backup_id = split["backup_id"].as_str().unwrap();
    let s2_hex = split["s2_hex"].as_str().unwrap();

    let (reg_handle, reg_request) = client_register_start(key_pin).unwrap();
    let (status, reg_resp) = post(
        &client,
        &format!("/wallets/{wallet_id}/backups/opaque/register/start"),
        serde_json::json!({
            "backup_id": backup_id,
            "request_b64": wallet_core::opaque::b64_encode(&reg_request),
        }),
    )
    .await;
    assert_eq!(status, 200, "register start");
    let upload = client_register_finish(
        &reg_handle,
        reg_resp["response_b64"].as_str().unwrap(),
        key_pin,
    )
    .unwrap();
    let (status, _) = post(
        &client,
        &format!("/wallets/{wallet_id}/backups/opaque/register/finish"),
        serde_json::json!({
            "backup_id": backup_id,
            "upload_b64": wallet_core::opaque::b64_encode(&upload),
        }),
    )
    .await;
    assert_eq!(status, 200, "register finish");

    let (status, _) = post(
        &client,
        &format!("/wallets/{wallet_id}/backups"),
        serde_json::json!({ "backup_id": backup_id, "s2_hex": s2_hex }),
    )
    .await;
    assert_eq!(status, 200, "escrow S2");

    // 3. OPAQUE login → S2 → combine (the restore flow).
    let (login_handle, login_request) = client_login_start(key_pin).unwrap();
    let (status, login_resp) = post(
        &client,
        &format!("/backups/{backup_id}/opaque/login/start"),
        serde_json::json!({
            "request_b64": wallet_core::opaque::b64_encode(&login_request),
        }),
    )
    .await;
    assert_eq!(status, 200, "login start: {login_resp}");
    let finalization = client_login_finish(
        &login_handle,
        login_resp["response_b64"].as_str().unwrap(),
        key_pin,
    )
    .unwrap();
    let (status, released) = post(
        &client,
        &format!("/backups/{backup_id}/opaque/login/finish"),
        serde_json::json!({
            "login_id": login_resp["login_id"].as_str().unwrap(),
            "finalization_b64": wallet_core::opaque::b64_encode(&finalization),
        }),
    )
    .await;
    assert_eq!(status, 200, "login finish: {released}");
    assert_eq!(released["s2_hex"].as_str().unwrap(), s2_hex);

    // S1 comes from the QR envelope; decrypt it here like the app does.
    let envelope: Value = serde_json::from_str(split["qr_payload"].as_str().unwrap()).unwrap();
    let s1_hex = wallet_core::api::decrypt_backup_share(
        envelope["s"].as_str().unwrap().to_string(),
        envelope["n"].as_str().unwrap().to_string(),
        envelope["c"].as_str().unwrap().to_string(),
        key_pin.to_string(),
    )
    .expect("unwrap S1");
    let recovered = wallet_core::api::combine_backup_shares(
        s1_hex,
        released["s2_hex"].as_str().unwrap().to_string(),
    )
    .expect("combine");
    assert_eq!(recovered, key.private_key_hex);
    let addr = wallet_core::api::address_from_private_key(recovered).unwrap();
    assert_eq!(addr, key.address_hex);

    // 4. Wrong PIN fails closed with a generic 401 (no oracle).
    let (bad_handle, bad_request) = client_login_start("wrong pin here").unwrap();
    let (status, bad_resp) = post(
        &client,
        &format!("/backups/{backup_id}/opaque/login/start"),
        serde_json::json!({
            "request_b64": wallet_core::opaque::b64_encode(&bad_request),
        }),
    )
    .await;
    assert_eq!(status, 200, "login start is blinded");
    let bad_final = client_login_finish(
        &bad_handle,
        bad_resp["response_b64"].as_str().unwrap(),
        "wrong pin here",
    );
    // Client-side may or may not reject; the server must.
    if let Ok(finalization) = bad_final {
        let (status, body) = post(
            &client,
            &format!("/backups/{backup_id}/opaque/login/finish"),
            serde_json::json!({
                "login_id": bad_resp["login_id"].as_str().unwrap(),
                "finalization_b64": wallet_core::opaque::b64_encode(&finalization),
            }),
        )
        .await;
        assert_eq!(status, 401, "wrong PIN fails closed: {body}");
    }

    // 5. Legacy release on an OPAQUE backup is refused, not downgraded.
    let (status, _) = post(
        &client,
        &format!("/backups/{backup_id}/release"),
        serde_json::json!({ "pin_hash": sha256_hex(wallet_pin) }),
    )
    .await;
    assert_eq!(status, 409, "no silent downgrade");
}
