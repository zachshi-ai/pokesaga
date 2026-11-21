use crate::{NitroData, Result, fixed, meshes, u16at, u32at};
use romkit::media::{Mesh, Texture, Wrap};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

/// Sample the terrain's own material names, UVs, and world vertices in the XZ plane.
/// Models remain separately identified so roofs cannot be misclassified as water or lanes.
pub fn section(data: &NitroData, land: usize, area: usize) -> Result<Value> {
    let bytes = &data.lands[land];
    let attrib = &data.areas[area];
    let tile_set = u16at(attrib, 2);
    let prop_set = u16at(attrib, 0);
    let start = 20 + u16at(bytes, 18) + u32at(bytes, 0);
    let terrain = start + u32at(bytes, 4);
    let geometry = meshes(
        &bytes[terrain..terrain + u32at(bytes, 8)],
        data.terrain_tex[tile_set].as_ref(),
    )?;
    let mut field = vec![(f32::NEG_INFINITY, 0usize, [0; 3]); 96 * 96];
    let mut mats = vec!["".to_owned()];
    let mut foliage = BTreeSet::new();
    for group in &geometry {
        sample_mesh(group, &mut field, &mut mats, &mut foliage);
    }
    let mut samples = Vec::new();
    for y in 0..32 {
        for x in 0..32 {
            let mut groups = BTreeMap::<usize, ([u32; 3], u32)>::new();
            for sy in 0..3 {
                for sx in 0..3 {
                    let (_, id, rgb) = field[(y * 3 + sy) * 96 + x * 3 + sx];
                    let (total, n) = groups.entry(id).or_default();
                    for i in 0..3 {
                        total[i] += rgb[i] as u32;
                    }
                    *n += 1;
                }
            }
            let (id, (sum, n)) = groups.into_iter().max_by_key(|(_, (_, k))| *k).unwrap();
            let rgb = sum.map(|s| s / n);
            samples.push([id as u32, rgb[0], rgb[1], rgb[2]]);
        }
    }
    let mut props = vec![];
    let bank = if attrib[6] != 0 {
        &data.outdoors
    } else {
        &data.indoors
    };
    for row in bytes[start..terrain].chunks_exact(48) {
        let id = u32at(row, 0);
        let geom = meshes(&bank[id], data.prop_tex[prop_set].as_ref())?;
        let model = geom.first().ok_or("prop no mesh")?;
        let (lo, hi) = model.bounds().unwrap_or(([0.; 3], [0.; 3]));
        props.push(json!([
            id,
            model.name,
            [fixed(row, 4) + 256., fixed(row, 8), fixed(row, 12) + 256.],
            lo,
            hi
        ]));
    }
    Ok(json!({"materials":mats,"surface":samples,"foliage":foliage,"props":props}))
}

fn sample_mesh(
    mesh: &Mesh,
    field: &mut [(f32, usize, [u8; 3])],
    mats: &mut Vec<String>,
    foliage: &mut BTreeSet<(i32, i32, String)>,
) {
    for part in &mesh.primitives {
        let Some(material) = part.material.and_then(|i| mesh.materials.get(i)) else {
            continue;
        };
        let name = material.name.to_lowercase();
        let id = if let Some(i) = mats.iter().position(|n| n == &name) {
            i
        } else {
            mats.push(name.clone());
            mats.len() - 1
        };
        let tex = material.texture.and_then(|i| mesh.textures.get(i));
        for tri in part.vertices.chunks_exact(3) {
            let [a, b, c] = [0, 1, 2].map(|i| tri[i].position);
            let mut lo = a;
            let mut hi = a;
            for v in [b, c] {
                for k in 0..3 {
                    lo[k] = lo[k].min(v[k]);
                    hi[k] = hi[k].max(v[k]);
                }
            }
            if (name.contains("tree") || name.contains("hayashi")) && hi[1] - lo[1] > 10. {
                let width = hi[0] - lo[0];
                if width >= 14. {
                    let pieces = (width / 32.).round().max(1.) as i32;
                    for i in 0..pieces {
                        let tx = lo[0] + (i as f32 + 0.5) * width / pieces as f32;
                        foliage.insert((
                            (tx + 256.).round() as i32,
                            (hi[2] + 256.).round() as i32,
                            name.clone(),
                        ));
                    }
                }
                continue;
            }
            let den = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2]);
            if den.abs() < 0.02 {
                continue;
            }
            let x0 = ((lo[0] + 256.) * 3. / 16.).floor().clamp(0., 96.) as usize;
            let x1 = ((hi[0] + 256.) * 3. / 16.).ceil().clamp(0., 96.) as usize;
            let z0 = ((lo[2] + 256.) * 3. / 16.).floor().clamp(0., 96.) as usize;
            let z1 = ((hi[2] + 256.) * 3. / 16.).ceil().clamp(0., 96.) as usize;
            for z in z0..z1 {
                for x in x0..x1 {
                    let px = (x as f32 + 0.5) * 16. / 3. - 256. - c[0];
                    let pz = (z as f32 + 0.5) * 16. / 3. - 256. - c[2];
                    let u = ((b[2] - c[2]) * px + (c[0] - b[0]) * pz) / den;
                    let v = ((c[2] - a[2]) * px + (a[0] - c[0]) * pz) / den;
                    let w = 1. - u - v;
                    if u < 0. || v < 0. || w < 0. {
                        continue;
                    }
                    let y = u * a[1] + v * b[1] + w * c[1];
                    let i = z * 96 + x;
                    if y + 0.002 < field[i].0 {
                        continue;
                    }
                    let rgba = tex.map_or(material.color, |t| {
                        texel(
                            t,
                            u * tri[0].uv[0] + v * tri[1].uv[0] + w * tri[2].uv[0],
                            u * tri[0].uv[1] + v * tri[1].uv[1] + w * tri[2].uv[1],
                        )
                    });
                    if rgba[3] > 64 {
                        field[i] = (y, id, [rgba[0], rgba[1], rgba[2]]);
                    }
                }
            }
        }
    }
}

fn texel(tex: &Texture, u: f32, v: f32) -> [u8; 4] {
    fn axis(v: f32, size: u32, wrap: Wrap) -> usize {
        let px = (v * size as f32).floor() as i32;
        let n = size as i32;
        (match wrap {
            Wrap::Clamp => px.clamp(0, n - 1),
            Wrap::Repeat => px.rem_euclid(n),
            Wrap::Mirror => {
                let p = px.rem_euclid(2 * n);
                if p < n { p } else { 2 * n - p - 1 }
            }
        }) as usize
    }
    let x = axis(u, tex.image.width, tex.wrap[0]);
    let y = axis(v, tex.image.height, tex.wrap[1]);
    tex.image.pixels[y * tex.image.width as usize + x]
}
