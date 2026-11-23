/* Per-tile samples of the X/Y field triangles, retaining the uppermost ground and prop. */
#include <stdint.h>
#include <math.h>
void surfaces(float *height, int16_t *ids, int width, int rows, const float *p, const uint32_t *idx,
              int triangles, int mat, int x0, int z0) {
    for (int i=0;i<triangles;i++) {
        const float *a=p+3*idx[3*i], *b=p+3*idx[3*i+1], *c=p+3*idx[3*i+2];
        float ax=a[0]/18-x0, ay=a[2]/18-z0, bx=b[0]/18-x0, by=b[2]/18-z0, cx=c[0]/18-x0, cy=c[2]/18-z0;
        float den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy);
        if(fabsf(den)<.001f)continue;
        int x1=fmaxf(0,floorf(fminf(ax,fminf(bx,cx)))),x2=fminf(width-1,ceilf(fmaxf(ax,fmaxf(bx,cx))));
        int y1=fmaxf(0,floorf(fminf(ay,fminf(by,cy)))),y2=fminf(rows-1,ceilf(fmaxf(ay,fmaxf(by,cy))));
        for(int y=y1;y<=y2;y++)for(int x=x1;x<=x2;x++) {
            float dx=x+.5f-cx,dy=y+.5f-cy,u=((by-cy)*dx+(cx-bx)*dy)/den,v=((cy-ay)*dx+(ax-cx)*dy)/den;
            if(u<-.00001f || v<-.00001f || u+v>1.00001f)continue;
            int cell=y*width+x;float h=u*a[1]+v*b[1]+(1-u-v)*c[1];
            if(h>=height[cell]){height[cell]=h;ids[cell]=mat;}
        }
    }
}
