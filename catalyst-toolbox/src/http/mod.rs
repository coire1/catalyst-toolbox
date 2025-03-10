use std::marker::PhantomData;

use ::reqwest::{blocking::Response, StatusCode};
use color_eyre::eyre::Result;
use log::warn;
use serde::Deserialize;

use self::{rate_limit::RateLimitClient, reqwest::ReqwestClient};

mod rate_limit;
mod reqwest;

const RATE_LIMIT_ENV_VAR: &str = "CATALYST_RATE_LIMIT_MS";

pub fn default_http_client(api_key: &str) -> impl HttpClient {
    let rate_limit = match std::env::var(RATE_LIMIT_ENV_VAR).map(|s| s.parse::<u64>()) {
        Ok(Ok(rate_limit)) => rate_limit,
        Ok(Err(_)) => {
            warn!(
                "{} could not be parsed as a u64, defaulting to no rate-limiting",
                RATE_LIMIT_ENV_VAR
            );
            0
        }
        _ => 0,
    };
    RateLimitClient::new(ReqwestClient::new(api_key), rate_limit)
}

#[cfg(test)]
#[allow(unused)]
fn test_default_client_send_sync() {
    fn check<T: Send + Sync>(_t: T) {}
    check(default_http_client(""));
}

/// Types which can make HTTP requests
pub trait HttpClient: Send + Sync + 'static {
    fn get<T>(&self, path: &str) -> Result<HttpResponse<T>>
    where
        T: for<'a> Deserialize<'a>;
}

/// A value returned from a HTTP method
pub struct HttpResponse<T: for<'a> Deserialize<'a>> {
    _marker: PhantomData<T>,
    inner: Response,
}

impl<T: for<'a> Deserialize<'a>> HttpResponse<T> {
    pub fn json(self) -> Result<T> {
        Ok(self.inner.json()?)
    }

    pub fn status(&self) -> StatusCode {
        self.inner.status()
    }
}
