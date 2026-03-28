//! 局域网 TCP 文件传输（协议 v1）：多文件单连接、UTF-8 元数据、流式读写。

use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};

use crate::api::types::{ApiError, FileReceiveEventDto, TransferProgressDto};
use crate::app_state::{now_ms_pub, push_progress, push_receive_event, with_state_mut};

const MAGIC: &[u8; 4] = b"XTX1";
const PROTO_VERSION: u16 = 1;
const MAX_MESSAGE_BYTES: usize = 64 * 1024;
const MAX_NAME_BYTES: usize = 512;
const MAX_SENDER_ID_BYTES: usize = 512;
const MAX_FILE_COUNT: u32 = 512;
const IO_BUF: usize = 64 * 1024;

fn io_err(msg: impl Into<String>, e: io::Error) -> ApiError {
    ApiError::new("FILE_IO", format!("{}: {e}", msg.into()))
}

fn write_all(stream: &mut TcpStream, mut data: &[u8]) -> Result<(), ApiError> {
    while !data.is_empty() {
        let n = stream.write(data).map_err(|e| io_err("写入套接字", e))?;
        if n == 0 {
            return Err(ApiError::new("FILE_IO", "写入套接字意外结束"));
        }
        data = &data[n..];
    }
    Ok(())
}

fn read_exact(stream: &mut TcpStream, buf: &mut [u8]) -> Result<(), ApiError> {
    let mut off = 0;
    while off < buf.len() {
        let n = stream
            .read(&mut buf[off..])
            .map_err(|e| io_err("读取套接字", e))?;
        if n == 0 {
            return Err(ApiError::new("FILE_IO", "连接对端提前关闭"));
        }
        off += n;
    }
    Ok(())
}

fn sanitize_saved_name(name: &str) -> String {
    let t = name.trim();
    if t.is_empty() {
        return "unnamed".to_string();
    }
    let bad = |c: char| {
        c == '/' || c == '\\' || c == ':' || c == '\0' || c == '\r' || c == '\n'
    };
    if t.contains("..") || t.chars().any(bad) {
        "unsafe_name".to_string()
    } else {
        t.to_string()
    }
}

fn unique_save_path(dir: &Path, original: &str) -> PathBuf {
    let safe = sanitize_saved_name(original);
    let path = dir.join(&safe);
    if !path.exists() {
        return path;
    }
    let p = Path::new(&safe);
    let stem = p
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("file");
    let ext = p
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{e}"))
        .unwrap_or_default();
    for i in 1_u32.. {
        let candidate = dir.join(format!("{stem}_{i}{ext}"));
        if !candidate.exists() {
            return candidate;
        }
    }
    dir.join(format!("{stem}_{}{ext}", u32::MAX))
}

fn basename_for_send(src: &Path) -> String {
    src.file_name()
        .and_then(|s| s.to_str())
        .map(|s| s.to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unnamed".to_string())
}

fn push_prog(transfer_id: &str, bytes_sent: i64, total_bytes: i64, phase: &str, err: Option<String>) {
    with_state_mut(|s| {
        push_progress(
            s,
            TransferProgressDto {
                transfer_id: transfer_id.to_string(),
                bytes_sent,
                total_bytes,
                phase: phase.to_string(),
                error: err,
            },
        );
    });
}

/// 阻塞发送：单 TCP 连接内依次写入头与多个文件正文。
pub fn send_files_blocking(
    host: &str,
    port: u16,
    sender_id: &str,
    message: &str,
    file_paths: &[String],
    transfer_id: &str,
    total_bytes: i64,
) -> Result<(), ApiError> {
    let sid = sender_id.as_bytes();
    if sid.len() > MAX_SENDER_ID_BYTES {
        return Err(ApiError::new(
            "INVALID_SENDER",
            format!("sender id 过长 (>{MAX_SENDER_ID_BYTES})"),
        ));
    }
    let msg_bytes = message.as_bytes();
    if msg_bytes.len() > MAX_MESSAGE_BYTES {
        return Err(ApiError::new(
            "MESSAGE_TOO_LONG",
            format!("留言过长 (>{MAX_MESSAGE_BYTES} 字节)"),
        ));
    }

    let addr = format!("{host}:{port}");
    push_prog(transfer_id, 0, total_bytes, "connecting", None);
    let mut stream = TcpStream::connect(addr.as_str()).map_err(|e| {
        ApiError::new(
            "TCP_CONNECT_FAILED",
            format!("无法连接 {addr}: {e}"),
        )
    })?;
    let _ = stream.set_nodelay(true);

    let nfiles = file_paths.len() as u32;
    if nfiles > MAX_FILE_COUNT {
        return Err(ApiError::new(
            "TOO_MANY_FILES",
            format!("一次最多发送 {MAX_FILE_COUNT} 个文件"),
        ));
    }

    let mut header = Vec::with_capacity(32 + sid.len() + msg_bytes.len());
    header.extend_from_slice(MAGIC);
    header.extend_from_slice(&PROTO_VERSION.to_le_bytes());
    header.extend_from_slice(&(sid.len() as u16).to_le_bytes());
    header.extend_from_slice(sid);
    header.extend_from_slice(&(msg_bytes.len() as u32).to_le_bytes());
    header.extend_from_slice(msg_bytes);
    header.extend_from_slice(&nfiles.to_le_bytes());
    write_all(&mut stream, &header)?;

    let mut sent: i64 = 0;
    push_prog(transfer_id, sent, total_bytes, "sending", None);

    for fp in file_paths {
        let path = Path::new(fp);
        let name = basename_for_send(path);
        let nb = name.as_bytes();
        if nb.len() > MAX_NAME_BYTES {
            return Err(ApiError::new(
                "NAME_TOO_LONG",
                format!("文件名过长: {name}"),
            ));
        }
        let mut f = File::open(path).map_err(|e| io_err(format!("打开 {fp}"), e))?;
        let size = f
            .metadata()
            .map_err(|e| io_err(format!("元数据 {fp}"), e))?
            .len();

        let mut meta = Vec::with_capacity(2 + nb.len() + 8);
        meta.extend_from_slice(&(nb.len() as u16).to_le_bytes());
        meta.extend_from_slice(nb);
        meta.extend_from_slice(&size.to_le_bytes());
        write_all(&mut stream, &meta)?;

        let mut buf = vec![0u8; IO_BUF];
        let mut remaining = size;
        while remaining > 0 {
            let to_read = (remaining as usize).min(IO_BUF);
            let n = f
                .read(&mut buf[..to_read])
                .map_err(|e| io_err(format!("读取 {fp}"), e))?;
            if n == 0 {
                return Err(ApiError::new("FILE_IO", format!("文件提前结束: {fp}")));
            }
            write_all(&mut stream, &buf[..n])?;
            remaining -= n as u64;
            sent += n as i64;
            push_prog(transfer_id, sent, total_bytes, "sending", None);
        }
    }

    push_prog(
        transfer_id,
        total_bytes,
        total_bytes,
        "completed",
        None,
    );
    Ok(())
}

fn read_u16(stream: &mut TcpStream) -> Result<u16, ApiError> {
    let mut b = [0u8; 2];
    read_exact(stream, &mut b)?;
    Ok(u16::from_le_bytes(b))
}

fn read_u32(stream: &mut TcpStream) -> Result<u32, ApiError> {
    let mut b = [0u8; 4];
    read_exact(stream, &mut b)?;
    Ok(u32::from_le_bytes(b))
}

fn read_u64(stream: &mut TcpStream) -> Result<u64, ApiError> {
    let mut b = [0u8; 8];
    read_exact(stream, &mut b)?;
    Ok(u64::from_le_bytes(b))
}

fn read_string(stream: &mut TcpStream, max_len: usize, label: &str) -> Result<String, ApiError> {
    let len = read_u32(stream)? as usize;
    if len > max_len {
        return Err(ApiError::new(
            "PROTO_BAD",
            format!("{label} 长度非法: {len}"),
        ));
    }
    let mut v = vec![0u8; len];
    read_exact(stream, &mut v)?;
    String::from_utf8(v).map_err(|_| ApiError::new("PROTO_BAD", format!("{label} 非 UTF-8")))
}

/// 处理一条入站连接：解析协议、落盘、推送接收事件。
pub fn handle_incoming_connection(mut stream: TcpStream) {
    let _ = stream.set_nodelay(true);
    let _ = handle_incoming_inner(&mut stream);
}

fn push_recv_err(
    file_name: String,
    message: String,
    sender_peer_id: String,
    err: String,
) {
    with_state_mut(|s| {
        push_receive_event(
            s,
            FileReceiveEventDto {
                file_name,
                message,
                sender_peer_id,
                saved_path: None,
                error: Some(err),
                timestamp_ms: now_ms_pub(),
            },
        );
    });
}

fn handle_incoming_inner(stream: &mut TcpStream) -> Result<(), ApiError> {
    let mut magic = [0u8; 4];
    if let Err(e) = read_exact(stream, &mut magic) {
        push_recv_err(String::new(), String::new(), String::new(), e.message);
        return Ok(());
    }
    if &magic != MAGIC {
        push_recv_err(
            String::new(),
            String::new(),
            String::new(),
            "非本应用文件协议（魔数不匹配）".to_string(),
        );
        return Ok(());
    }
    let ver = match read_u16(stream) {
        Ok(v) => v,
        Err(e) => {
            push_recv_err(String::new(), String::new(), String::new(), e.message);
            return Ok(());
        }
    };
    if ver != PROTO_VERSION {
        push_recv_err(
            String::new(),
            String::new(),
            String::new(),
            format!("协议版本不支持: {ver}"),
        );
        return Ok(());
    }

    let sid_len = match read_u16(stream) {
        Ok(v) => v as usize,
        Err(e) => {
            push_recv_err(String::new(), String::new(), String::new(), e.message);
            return Ok(());
        }
    };
    if sid_len > MAX_SENDER_ID_BYTES {
        push_recv_err(
            String::new(),
            String::new(),
            String::new(),
            "发送方 ID 过长".to_string(),
        );
        return Ok(());
    }
    let mut sid_buf = vec![0u8; sid_len];
    if let Err(e) = read_exact(stream, &mut sid_buf) {
        push_recv_err(String::new(), String::new(), String::new(), e.message);
        return Ok(());
    }
    let sender_id = match String::from_utf8(sid_buf) {
        Ok(s) => s,
        Err(_) => {
            push_recv_err(
                String::new(),
                String::new(),
                String::new(),
                "发送方 ID 非 UTF-8".to_string(),
            );
            return Ok(());
        }
    };

    let message = match read_string(stream, MAX_MESSAGE_BYTES, "留言") {
        Ok(m) => m,
        Err(e) => {
            push_recv_err(String::new(), String::new(), sender_id, e.message);
            return Ok(());
        }
    };

    let nfiles = match read_u32(stream) {
        Ok(n) => n,
        Err(e) => {
            push_recv_err(String::new(), message, sender_id, e.message);
            return Ok(());
        }
    };
    if nfiles > MAX_FILE_COUNT {
        push_recv_err(
            String::new(),
            message.clone(),
            sender_id.clone(),
            "文件数量异常".to_string(),
        );
        return Ok(());
    }

    let receive_dir = crate::app_state::with_state(|s| s.receive_path.clone());
    let Some(dir) = receive_dir else {
        push_recv_err(
            String::new(),
            message.clone(),
            sender_id.clone(),
            "未设置接收目录，无法保存文件".to_string(),
        );
        return Ok(());
    };

    for _ in 0..nfiles {
        let name_len = match read_u16(stream) {
            Ok(v) => v as usize,
            Err(e) => {
                push_recv_err(String::new(), message.clone(), sender_id.clone(), e.message);
                return Ok(());
            }
        };
        if name_len > MAX_NAME_BYTES {
            push_recv_err(
                String::new(),
                message.clone(),
                sender_id.clone(),
                "文件名过长".to_string(),
            );
            return Ok(());
        }
        let mut nb = vec![0u8; name_len];
        if let Err(e) = read_exact(stream, &mut nb) {
            push_recv_err(String::new(), message.clone(), sender_id.clone(), e.message);
            return Ok(());
        }
        let raw_name = match String::from_utf8(nb) {
            Ok(s) => s,
            Err(_) => {
                push_recv_err(
                    String::new(),
                    message.clone(),
                    sender_id.clone(),
                    "文件名非 UTF-8".to_string(),
                );
                return Ok(());
            }
        };
        let size = match read_u64(stream) {
            Ok(s) => s,
            Err(e) => {
                push_recv_err(
                    raw_name.clone(),
                    message.clone(),
                    sender_id.clone(),
                    e.message,
                );
                return Ok(());
            }
        };

        let save_path = unique_save_path(&dir, &raw_name);
        let copy_result = copy_n_from_stream(stream, &save_path, size);
        match copy_result {
            Ok(()) => {
                let saved = save_path.to_string_lossy().into_owned();
                with_state_mut(|s| {
                    push_receive_event(
                        s,
                        FileReceiveEventDto {
                            file_name: raw_name.clone(),
                            message: message.clone(),
                            sender_peer_id: sender_id.clone(),
                            saved_path: Some(saved),
                            error: None,
                            timestamp_ms: now_ms_pub(),
                        },
                    );
                });
            }
            Err(e) => {
                push_recv_err(
                    raw_name,
                    message.clone(),
                    sender_id.clone(),
                    e.message,
                );
                return Ok(());
            }
        }
    }

    Ok(())
}

fn copy_n_from_stream(stream: &mut TcpStream, path: &Path, total: u64) -> Result<(), ApiError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| io_err("创建接收子目录", e))?;
    }
    let mut out = File::create(path).map_err(|e| io_err("创建接收文件", e))?;
    let mut remaining = total;
    let mut buf = vec![0u8; IO_BUF];
    while remaining > 0 {
        let chunk = (remaining as usize).min(IO_BUF);
        let n = stream
            .read(&mut buf[..chunk])
            .map_err(|e| io_err("接收文件数据", e))?;
        if n == 0 {
            return Err(ApiError::new("FILE_IO", "对端提前结束，文件不完整"));
        }
        out.write_all(&buf[..n])
            .map_err(|e| io_err("写入接收文件", e))?;
        remaining -= n as u64;
    }
    Ok(())
}
