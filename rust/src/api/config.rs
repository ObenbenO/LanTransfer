//! 初始化、本机标识、接收目录与本地身份快照。

use std::fs;
use std::path::PathBuf;

use uuid::Uuid;

use crate::app_state::{validate_receive_dir, with_state, with_state_mut, AppState};
use super::types::{ApiError, LocalProfileDto};

#[flutter_rust_bridge::frb(init)]
pub fn init_rust_lib() {
    flutter_rust_bridge::setup_default_user_utils();
    with_state_mut(|s| {
        if s.initialized {
            return;
        }
        s.device_id = AppState::load_or_create_device_id(s.cache_dir.clone());
        s.session_id = Uuid::new_v4().to_string();
        s.initialized = true;
    });
}

/// 配置持久化设备 ID 的目录；不传则使用系统临时目录下的子目录。
#[flutter_rust_bridge::frb(sync)]
pub fn set_rust_cache_dir(path: String) -> Result<(), ApiError> {
    let p = PathBuf::from(path.trim());
    fs::create_dir_all(&p).map_err(|e| {
        ApiError::new(
            "CACHE_DIR_CREATE",
            format!("无法创建缓存目录: {e}"),
        )
    })?;
    with_state_mut(|s| {
        s.cache_dir = Some(p.clone());
        s.device_id = AppState::load_or_create_device_id(Some(p));
    });
    Ok(())
}

/// 释放监听线程等资源；再次使用需由 Flutter 重新 `RustLib.init()`（或后续扩展热启动 API）。
#[flutter_rust_bridge::frb(sync)]
pub fn shutdown_rust_lib() -> Result<(), ApiError> {
    with_state_mut(|s| {
        s.file_service.take();
        s.remote_host_service.take();
        s.file_listen_port = None;
        s.remote_host_port = None;
        s.remote_host_token = None;
        s.remote_client_peer = None;
        s.remote_client_token = None;
        s.initialized = false;
    });
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn device_id() -> Result<String, ApiError> {
    with_state(|s| {
        if !s.initialized {
            return Err(ApiError::new(
                "NOT_INITIALIZED",
                "请先完成 Rust 初始化（RustLib.init）",
            ));
        }
        Ok(s.device_id.clone())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn session_id() -> Result<String, ApiError> {
    with_state(|s| {
        if !s.initialized {
            return Err(ApiError::new("NOT_INITIALIZED", "请先完成 Rust 初始化"));
        }
        Ok(s.session_id.clone())
    })
}

/// 生成新的会话 ID（例如用户重新登录）。
#[flutter_rust_bridge::frb(sync)]
pub fn refresh_session_id() -> Result<String, ApiError> {
    with_state_mut(|s| {
        if !s.initialized {
            return Err(ApiError::new("NOT_INITIALIZED", "请先完成 Rust 初始化"));
        }
        s.session_id = Uuid::new_v4().to_string();
        Ok(s.session_id.clone())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_default_receive_path(path: String) -> Result<(), ApiError> {
    let pb = validate_receive_dir(&path)?;
    with_state_mut(|s| {
        if !s.initialized {
            return Err(ApiError::new("NOT_INITIALIZED", "请先完成 Rust 初始化"));
        }
        s.receive_path = Some(pb);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_default_receive_path() -> Option<String> {
    with_state(|s| s.receive_path.as_ref().map(|p| p.to_string_lossy().into_owned()))
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_local_profile(profile: LocalProfileDto) -> Result<(), ApiError> {
    with_state_mut(|s| {
        if !s.initialized {
            return Err(ApiError::new("NOT_INITIALIZED", "请先完成 Rust 初始化"));
        }
        s.profile = Some(profile);
        Ok(())
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_local_profile() -> Option<LocalProfileDto> {
    with_state(|s| s.profile.clone())
}
