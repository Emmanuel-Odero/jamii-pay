use axum::{http::StatusCode, response::IntoResponse, response::Response, Json};
use serde::Serialize;

/// Shared error type for every route handler. Keeps `sqlx::Error` (and any
/// other internal detail) out of HTTP responses — clients get a status
/// code and a short message, nothing that leaks schema or query shape.
pub enum ApiError {
    NotFound(&'static str),
    Conflict(&'static str),
    BadRequest(String),
    Unauthorized(&'static str),
    /// 423 Locked — throttle exhausted (backup releases) or otherwise
    /// temporarily unavailable by policy. Distinct from 401 so clients can
    /// show "try later, guardians alerted" instead of "wrong PIN".
    Locked(&'static str),
    /// 410 Gone — the resource (a backup) was revoked. Distinct from 404
    /// so clients can route to recovery guardians instead of retrying.
    Gone(&'static str),
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for ApiError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => ApiError::NotFound("not found"),
            other => ApiError::Internal(other.into()),
        }
    }
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.to_string()),
            ApiError::Conflict(msg) => (StatusCode::CONFLICT, msg.to_string()),
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            ApiError::Unauthorized(msg) => (StatusCode::UNAUTHORIZED, msg.to_string()),
            ApiError::Locked(msg) => (StatusCode::LOCKED, msg.to_string()),
            ApiError::Gone(msg) => (StatusCode::GONE, msg.to_string()),
            ApiError::Internal(err) => {
                tracing::error!(error = %err, "internal error handling request");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal error".to_string(),
                )
            }
        };

        (status, Json(ErrorBody { error: message })).into_response()
    }
}

pub type ApiResult<T> = Result<T, ApiError>;
