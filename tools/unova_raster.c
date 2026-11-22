/* Orthographic field painting. Mesh coordinates, UVs, and alpha cutouts come from the map. */
#include <math.h>
#include <stdint.h>
void draw_triangles(uint8_t *pixels,float *depth,int width,int height,const float *vertices,
                    const uint32_t *indices,int faces,const uint8_t *texture,int tw,int th) {
    for(int i=0;i<faces;i++) {
        const float *a=vertices+indices[i*3]*5,*b=vertices+indices[i*3+1]*5,*c=vertices+indices[i*3+2]*5;
        float denominator=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);
        if(fabsf(denominator)<.01f) continue;
        int left=fmaxf(0,floorf(fminf(a[0],fminf(b[0],c[0])))),right=fminf(width-1,ceilf(fmaxf(a[0],fmaxf(b[0],c[0]))));
        int top=fmaxf(0,floorf(fminf(a[1],fminf(b[1],c[1])))),bottom=fminf(height-1,ceilf(fmaxf(a[1],fmaxf(b[1],c[1]))));
        for(int y=top;y<=bottom;y++) for(int x=left;x<=right;x++) {
            float dx=x+.5f-c[0],dy=y+.5f-c[1],u=((b[1]-c[1])*dx+(c[0]-b[0])*dy)/denominator;
            float v=((c[1]-a[1])*dx+(a[0]-c[0])*dy)/denominator,w=1-u-v;
            if(u<0 || v<0 || w<0)continue;
            int dest=y*width+x;
            float z=u*a[2]+v*b[2]+w*c[2];
            if(z<depth[dest])continue;
            int tx=(int)floorf((u*a[3]+v*b[3]+w*c[3])*tw),ty=(int)floorf((u*a[4]+v*b[4]+w*c[4])*th);
            tx=((tx%tw)+tw)%tw;ty=((ty%th)+th)%th;
            const uint8_t *source=texture+4*(ty*tw+tx);
            if(source[3]<128)continue;
            for(int channel=0;channel<4;channel++)pixels[dest*4+channel]=source[channel];
            depth[dest]=z;
        }
    }
}
