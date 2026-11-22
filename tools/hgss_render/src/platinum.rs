use crate::{Result, meshes, semantic::terrain_cells, u32at};
use romkit::formats::nitro3d::Textures;
use serde_json::{Value, json};
use std::{collections::BTreeMap, env, fs, path::PathBuf};

/// Platinum's area data and model archives are already split in the source tree.
/// Decode the original terrain mesh UV/material for each cell, independently of buildings.
pub fn run() -> Result<()> {
    let args: Vec<_> = env::args_os().skip(2).collect();
    if args.len() != 3 {
        return Err("expected Platinum checkout, matrix job list, and output directory".into());
    }
    let root = PathBuf::from(&args[0]).join("res/field");
    let jobs: Vec<(usize, usize)> = serde_json::from_slice(&fs::read(&args[1])?)?;
    let out = PathBuf::from(&args[2]);
    fs::create_dir_all(&out)?;
    let mut textures = BTreeMap::new();
    let mut prop_names = BTreeMap::new();
    let models = fs::read_to_string(root.join("props/models/map_prop_models.order"))?;
    let files: Vec<_> = models.lines().collect();
    let effects = PathBuf::from(&args[0]).join("res/graphics/field_effects");
    let mut platforms = BTreeMap::new();
    for entry in fs::read_dir(effects)? {
        let path = entry?.path();
        let stem = path.file_stem().unwrap().to_string_lossy().into_owned();
        if !stem.starts_with("distortion_world_")
            || !stem.contains("platform")
            || path.extension().and_then(|s| s.to_str()) != Some("nsbmd")
        {
            continue;
        }
        let mesh = meshes(&fs::read(path)?, None)?;
        let (_, surface, _) = terrain_cells(&mesh);
        let cells: Vec<_> = surface
            .iter()
            .enumerate()
            .filter(|(_, v)| v[0] != 0)
            .map(|(k, _)| [(k % 32) as i32 - 16, (k / 32) as i32 - 16])
            .collect();
        platforms.insert(stem, cells);
    }
    fs::write(
        out.join("distortion_platforms.json"),
        serde_json::to_vec(&platforms)?,
    )?;
    for (land, area) in jobs {
        let path = out.join(format!("{land}_{area}.json"));
        let header: Value = serde_json::from_slice(&fs::read(
            root.join(format!("area_data/area_data_{area:03}.json")),
        )?)?;
        let tex_name = header["mapTextureSet"]
            .as_str()
            .ok_or("missing mapTextureSet")?;
        if !textures.contains_key(tex_name) {
            let data = fs::read(root.join(format!("mapmodels/texture_sets/{tex_name}.nsbtx")))?;
            textures.insert(tex_name.to_owned(), Textures::parse(&data).ok());
        }
        let bytes = fs::read(root.join(format!("mapmodels/data/map_data_{land:03}.bin")))?;
        let props_start = 16 + u32at(&bytes, 0);
        let terrain = props_start + u32at(&bytes, 4);
        let geom = meshes(
            &bytes[terrain..terrain + u32at(&bytes, 8)],
            textures[tex_name].as_ref(),
        )?;
        let (mats, surface, foliage) = terrain_cells(&geom);
        let mut props = vec![];
        for row in bytes[props_start..terrain].chunks_exact(48) {
            let id = u32at(row, 0);
            if !prop_names.contains_key(&id) {
                let b = fs::read(root.join("props/models").join(files[id]))?;
                let name = romkit::formats::nitro3d::Nsbmd::parse(&b)?
                    .models
                    .first()
                    .map(|m| m.name.clone())
                    .unwrap_or_default();
                prop_names.insert(id, name);
            }
            props.push(json!([
                id,
                prop_names[&id],
                crate::fixed(row, 4) / 16. + 16.,
                crate::fixed(row, 12) / 16. + 16.
            ]));
        }
        fs::write(
            path,
            serde_json::to_vec(
                &json!({"materials":mats,"surface":surface,"foliage":foliage,"props":props}),
            )?,
        )?;
    }
    Ok(())
}
