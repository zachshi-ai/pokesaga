"""Read the X/Y atlas's quantized meshopt GLBs and keep the cartridge's world coordinates."""
from functools import lru_cache
from io import BytesIO
import gzip
import json
import struct
import meshoptimizer
import numpy as np
from PIL import Image


class FieldModel:
    def __init__(self, path):
        raw = gzip.open(path, 'rb').read()
        length = struct.unpack_from('<I', raw, 12)[0]
        self.gltf = json.loads(raw[20:20+length])
        self.buffer = raw[28+length:]
        self.images = {}
        self.buffers = {}

    def view(self, index):
        if index not in self.buffers:
            info = self.gltf['bufferViews'][index]
            src = info.get('extensions', {}).get('EXT_meshopt_compression')
            if src:
                offset = src.get('byteOffset', 0)
                data = self.buffer[offset:offset+src['byteLength']]
                count, stride = src['count'], src['byteStride']
                if src['mode'] == 'ATTRIBUTES':
                    result = meshoptimizer.decode_vertex_buffer(count, stride, data, dtype=np.dtype((np.uint8, stride))).tobytes()
                elif src['mode'] == 'TRIANGLES':
                    result = meshoptimizer.decode_index_buffer(count, stride, data).tobytes()[:count*stride]
                else:
                    raise ValueError(src['mode'])
            else:
                offset = info.get('byteOffset', 0)
                result = self.buffer[offset:offset+info['byteLength']]
            self.buffers[index] = result
        return self.buffers[index]

    def values(self, index):
        a = self.gltf['accessors'][index]
        typ = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
        dim = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        size = np.dtype(typ).itemsize
        stride = self.gltf['bufferViews'][a['bufferView']].get('byteStride',dim*size)
        return np.ndarray((a['count'],dim),dtype=typ,buffer=self.view(a['bufferView']),
                          offset=a.get('byteOffset',0),strides=(stride,size))

    def texture(self, mat):
        sm = mat['extras']['sm']
        texs = [(name, texture, i) for i,(name,texture) in enumerate(zip(sm['names'],sm['textures'])) if name and texture is not None]
        def preferred(row):
            name = row[0].lower()
            if any(word in name for word in ('dummy','shadow','kokage','_mask','_ref','_nor')): return -2
            if name.endswith(('_s','_sp','_sha','_bump','_n')): return -1
            return 5 if name == mat['name'].lower() else 1
        if not texs:
            return np.full((1,1,4),255,np.uint8),0
        _,tex,uv = max(texs,key=preferred)
        tid = self.gltf['textures'][tex]['extensions']['EXT_texture_webp']['source']
        if tid not in self.images:
            blob = self.view(self.gltf['images'][tid]['bufferView'])
            self.images[tid] = np.asarray(Image.open(BytesIO(blob)).convert('RGBA'))
        return self.images[tid],uv

    def parts(self):
        for m in self.gltf['meshes']:
            for p in m['primitives']:
                a = p['attributes']
                q = p.get('extras',{}).get('q',{})
                pos = self.values(a['POSITION']).astype(np.float32)
                if 'position' in q: pos = (pos+q['position'][:3])*q['position'][3]
                mat = self.gltf['materials'][p['material']]
                texture,uvslot = self.texture(mat)
                field = 'TEXCOORD_'+str(uvslot)
                if field not in a:
                    field='TEXCOORD_0';uvslot=0
                uv = self.values(a[field]).astype(np.float32) if field in a else np.zeros((len(pos),2),np.float32)
                key='uv'+(str(uvslot) if uvslot else '')
                if key in q: uv=(uv+q[key][:2])*q[key][2]
                idx = self.values(p['indices']).reshape((-1,3)).astype(np.uint32)
                assert idx.max()<len(pos),(m['name'],idx.max(),len(pos))
                yield m['name'],mat['name'],pos.astype(np.float32),uv.astype(np.float32),idx,texture,mat
