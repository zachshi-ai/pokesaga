mod semantic;

use romkit::formats::{
    narc::Narc,
    nitro3d::{Nsbmd, Textures},
};
use romkit::media::Mesh;
use serde_json::Value;
use std::{
    collections::BTreeSet,
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
};

type Result<T> = std::result::Result<T, Box<dyn Error>>;
type Key = (usize, usize);

fn u16at(b: &[u8], o: usize) -> usize {
    u16::from_le_bytes(b[o..o + 2].try_into().unwrap()) as usize
}
fn u32at(b: &[u8], o: usize) -> usize {
    u32::from_le_bytes(b[o..o + 4].try_into().unwrap()) as usize
}
fn fixed(b: &[u8], o: usize) -> f32 {
    i32::from_le_bytes(b[o..o + 4].try_into().unwrap()) as f32 / 4096.
}
fn archive(root: &Path, path: &str) -> Result<Vec<Vec<u8>>> {
    let bytes = fs::read(root.join(path))?;
    let index = Narc::parse(&bytes)?;
    Ok((0..index.len())
        .map(|i| index.member(&bytes, i).map(|s| s.into_owned()))
        .collect::<std::result::Result<_, _>>()?)
}
struct NitroData {
    lands: Vec<Vec<u8>>,
    areas: Vec<Vec<u8>>,
    terrain_tex: Vec<Option<Textures>>,
    prop_tex: Vec<Option<Textures>>,
    outdoors: Vec<Vec<u8>>,
    indoors: Vec<Vec<u8>>,
}

fn textures(root: &Path, path: &str) -> Result<Vec<Option<Textures>>> {
    archive(root, path)?
        .iter()
        .map(|b| {
            if b.as_slice() == [0, 0, 0, 0] {
                Ok(None)
            } else {
                Ok(Some(Textures::parse(b)?))
            }
        })
        .collect()
}

impl NitroData {
    fn open(dir: &Path) -> Result<Self> {
        Ok(Self {
            lands: archive(dir, "a/0/6/5")?,
            areas: archive(dir, "a/0/4/2")?,
            terrain_tex: textures(dir, "a/0/4/4")?,
            prop_tex: textures(dir, "a/0/7/0")?,
            outdoors: archive(dir, "a/0/4/0")?,
            indoors: archive(dir, "a/1/4/8")?,
        })
    }
}

fn meshes(bmd: &[u8], shared: Option<&Textures>) -> Result<Vec<Mesh>> {
    let file = Nsbmd::parse(bmd)?;
    let banks = file.textures.iter().chain(shared).collect::<Vec<_>>();
    Ok(file
        .models
        .iter()
        .map(|m| m.mesh(&banks))
        .collect::<std::result::Result<_, _>>()?)
}

fn main() -> Result<()> {
    let mut args = env::args_os().skip(1);
    let src = PathBuf::from(
        args.next()
            .ok_or("expected pokeheartgold source directory")?,
    )
    .join("files");
    let events = PathBuf::from(args.next().ok_or("expected events.json")?);
    let out = PathBuf::from(args.next().ok_or("expected output directory")?);
    let selected: BTreeSet<_> = args.map(|s| s.to_string_lossy().into_owned()).collect();
    let doc: Value = serde_json::from_slice(&fs::read(&events)?)?;
    let headers = doc["headers"].as_object().ok_or("missing headers")?;
    let mut wanted = BTreeSet::<Key>::new();
    for (key, header) in headers {
        if !selected.is_empty() && !selected.contains(key) {
            continue;
        }
        if let (Some(area), Some(entries)) = (
            header["area_data_id"].as_u64(),
            header["entries"].as_array(),
        ) {
            for land in entries.iter().filter_map(|e| e["land_id"].as_u64()) {
                if land < 65535 {
                    wanted.insert((land as usize, area as usize));
                }
            }
        }
    }
    if wanted.is_empty() {
        return Err("no matrices selected".into());
    }
    fs::create_dir_all(&out)?;
    let data = NitroData::open(&src)?;
    for (land, area) in wanted {
        let info = semantic::section(&data, land, area)?;
        fs::write(
            out.join(format!("{land}_{area}.json")),
            serde_json::to_vec(&info)?,
        )?;
    }
    Ok(())
}
