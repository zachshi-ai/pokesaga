//! Decode the actual Platinum terrain and the prop bank selected by each area header.
//! Intermediate GLBs are build inputs only. The game reads 16-pixel 2-D paintings.
use romkit::formats::nitro3d::{Nsbmd, Textures};
use serde_json::Value;
use std::{
    collections::HashMap,
    env,
    error::Error,
    fs,
    path::{Path, PathBuf},
};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn model(bytes: &[u8], shared: Option<&Textures>, out: &Path) -> Result<()> {
    if out.exists() {
        return Ok(());
    }
    let doc = Nsbmd::parse(bytes)?;
    let banks: Vec<_> = doc.textures.iter().chain(shared).collect();
    let gd = doc.models.first().ok_or("empty model")?.mesh(&banks)?;
    fs::write(out, gd.to_glb()?)?;
    Ok(())
}

fn word(bytes: &[u8], offset: usize) -> usize {
    u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize
}

fn main() -> Result<()> {
    let mut args = env::args_os().skip(1);
    let root = PathBuf::from(args.next().ok_or("Platinum checkout")?).join("res/field");
    let jobs: Vec<(usize, usize)> =
        serde_json::from_slice(&fs::read(args.next().ok_or("jobs JSON")?)?)?;
    let out = PathBuf::from(args.next().ok_or("mesh cache")?);
    fs::create_dir_all(&out)?;
    let files = fs::read_to_string(root.join("props/models/map_prop_models.order"))?;
    let files: Vec<_> = files.lines().collect();
    let mut textures: HashMap<String, Option<Textures>> = HashMap::new();
    for (land, area) in jobs {
        let header: Value = serde_json::from_slice(&fs::read(
            root.join(format!("area_data/area_data_{area:03}.json")),
        )?)?;
        let set = header["mapTextureSet"].as_str().ok_or("terrain bank")?;
        let prop_set = header["mapPropSet"]
            .as_str()
            .ok_or("prop bank")?
            .replace("model", "texture");
        for (key, folder) in [
            (set, "mapmodels/texture_sets"),
            (&prop_set, "props/texture_sets"),
        ] {
            if !textures.contains_key(key) {
                let raw = fs::read(root.join(folder).join(format!("{key}.nsbtx")))?;
                textures.insert(key.to_owned(), Textures::parse(&raw).ok());
            }
        }
        let data = fs::read(root.join(format!("mapmodels/data/map_data_{land:03}.bin")))?;
        let p = 16 + word(&data, 0);
        let geo = p + word(&data, 4);
        model(
            &data[geo..geo + word(&data, 8)],
            textures[set].as_ref(),
            &out.join(format!("ground_{land}_{area}.glb")),
        )?;
        for row in data[p..geo].chunks_exact(48) {
            let id = word(row, 0);
            let file = out.join(format!("{prop_set}_{id}.glb"));
            if !file.exists() {
                model(
                    &fs::read(root.join("props/models").join(files[id]))?,
                    textures[&prop_set].as_ref(),
                    &file,
                )?;
            }
        }
    }
    Ok(())
}
