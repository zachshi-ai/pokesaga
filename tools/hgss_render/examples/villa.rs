use romkit::formats::nitro3d::{Nsbmd, Textures};
use serde_json::json;
use std::{env, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args_os().skip(1);
    let pt = PathBuf::from(args.next().ok_or("Platinum source directory")?);
    let out = PathBuf::from(args.next().ok_or("mesh output directory")?);
    let props = pt.join("res/field/props");
    let shared = Textures::parse(&fs::read(
        props.join("texture_sets/prop_texture_set_047.nsbtx"),
    )?)?;
    fs::create_dir_all(&out)?;
    for entry in fs::read_dir(props.join("models"))? {
        let path = entry?.path();
        let stem = path.file_stem().and_then(|v| v.to_str()).unwrap_or("");
        let Some(key) = stem.strip_prefix("villa_furniture_") else {
            continue;
        };
        let file = Nsbmd::parse(&fs::read(&path)?)?;
        let textures = file
            .textures
            .iter()
            .chain(std::iter::once(&shared))
            .collect::<Vec<_>>();
        let mesh = file.models[0].mesh(&textures)?;
        for (i, tex) in mesh.textures.iter().enumerate() {
            fs::write(out.join(format!("{key}_{i}.png")), tex.image.to_png()?)?;
        }
        let parts = mesh
            .primitives
            .iter()
            .map(|p| {
                let m = &mesh.materials[p.material.unwrap_or(0)];
                let vertices = p
                    .vertices
                    .iter()
                    .map(|v| json!([v.position, v.uv, v.color]))
                    .collect::<Vec<_>>();
                json!({"texture":m.texture,"color":m.color,"vertices":vertices})
            })
            .collect::<Vec<_>>();
        fs::write(out.join(format!("{key}.json")), serde_json::to_vec(&parts)?)?;
    }
    Ok(())
}
