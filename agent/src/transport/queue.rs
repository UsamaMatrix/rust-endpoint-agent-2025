use anyhow::Result;
use rand::{distributions::Alphanumeric, Rng};
use std::path::{Path, PathBuf};
use tokio::{fs, io::AsyncWriteExt};
pub struct DiskQueue {
    dir: PathBuf,
    cap_bytes: u64,
}
impl DiskQueue {
    pub async fn open(dir: &Path, cap: u64) -> Result<Self> {
        fs::create_dir_all(dir).await?;
        Ok(Self {
            dir: dir.to_path_buf(),
            cap_bytes: cap,
        })
    }
    pub async fn enqueue(&mut self, data: Vec<u8>) -> Result<()> {
        self.enforce_cap().await?;
        let name = format!("{}-{}.ndjson", now_ms(), rand_str(6));
        let p = self.dir.join(name);
        let mut f = fs::File::create(&p).await?;
        f.write_all(&data).await?;
        Ok(())
    }
    pub async fn peek_oldest(&self) -> Result<Option<Vec<u8>>> {
        let mut rd = fs::read_dir(&self.dir).await?;
        let mut files: Vec<PathBuf> = Vec::new();
        while let Some(e) = rd.next_entry().await? {
            if e.metadata().await?.is_file() {
                files.push(e.path());
            }
        }
        files.sort();
        if let Some(f) = files.first() {
            return Ok(Some(fs::read(f).await?));
        }
        Ok(None)
    }
    pub async fn pop_oldest(&self) -> Result<()> {
        let mut rd = fs::read_dir(&self.dir).await?;
        let mut files: Vec<PathBuf> = Vec::new();
        while let Some(e) = rd.next_entry().await? {
            if e.metadata().await?.is_file() {
                files.push(e.path());
            }
        }
        files.sort();
        if let Some(f) = files.first() {
            fs::remove_file(f).await?;
        }
        Ok(())
    }
    async fn enforce_cap(&self) -> Result<()> {
        let mut rd = fs::read_dir(&self.dir).await?;
        let mut files: Vec<(PathBuf, u64)> = Vec::new();
        let mut total = 0u64;
        while let Some(e) = rd.next_entry().await? {
            let p = e.path();
            let md = e.metadata().await?;
            if md.is_file() {
                let sz = md.len();
                total += sz;
                files.push((p, sz));
            }
        }
        files.sort_by(|a, b| a.0.cmp(&b.0));
        while total > self.cap_bytes {
            if let Some((old, sz)) = files.first().cloned() {
                let _ = fs::remove_file(&old).await;
                total = total.saturating_sub(sz);
                files.remove(0);
            } else {
                break;
            }
        }
        Ok(())
    }
}
fn rand_str(n: usize) -> String {
    rand::thread_rng()
        .sample_iter(&Alphanumeric)
        .take(n)
        .map(char::from)
        .collect()
}
fn now_ms() -> i128 {
    use time::OffsetDateTime;
    OffsetDateTime::now_utc().unix_timestamp_nanos() as i128 / 1_000_000
}
