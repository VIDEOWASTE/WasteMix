// Used by tools/screenshots/shoot.sh.
// Renders 4 colorful 1920x1080 stills (PPM) for simulator screenshots.
#include <cmath>
#include <cstdio>
static unsigned char q(float v){ v = v < 0 ? 0 : v > 1 ? 1 : v; return (unsigned char)(v * 255); }
int main() {
    const int W = 1920, H = 1080; const float t = 1.7f;
    for (int s = 0; s < 4; s++) {
        char name[32]; snprintf(name, sizeof name, "demo%d.ppm", s + 1);
        FILE* f = fopen(name, "wb"); fprintf(f, "P6\n%d %d\n255\n", W, H);
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            float u = (x - W / 2.f) / H, v = (y - H / 2.f) / H, r, g, b;
            if (s == 0) {        // plasma
                float p = sinf(u*9+t)+sinf(v*7-t*1.3f)+sinf((u+v)*6+t*.7f)+sinf(sqrtf(u*u+v*v)*14-t*2);
                r = .5f+.5f*sinf(p*1.6f); g = .5f+.5f*sinf(p*1.6f+2.1f); b = .5f+.5f*sinf(p*1.6f+4.2f);
            } else if (s == 1) { // neon rings
                float d = sqrtf(u*u+v*v), k = powf(.5f+.5f*sinf(d*40-t*5), 6);
                r = k; g = k*.15f; b = k*(.6f+.4f*sinf(d*6+t));
            } else if (s == 2) { // cyan stripes
                float k = .5f+.5f*sinf((u*cosf(.5f)+v*sinf(.5f))*30+t*4); k = k > .55f ? 1.f : .05f;
                r = k*.1f; g = k*.9f; b = k;
            } else {             // sunset tunnel
                float a = atan2f(v, u), d = sqrtf(u*u+v*v)+1e-3f, z = 1.f/d;
                float k = .5f+.5f*sinf(z*6+a*6); float fade = fminf(d*1.6f, 1.f);
                r = fade*(.9f*k+.1f); g = fade*(.35f*k); b = fade*(.6f*(1-k)+.2f);
            }
            unsigned char px[3] = { q(r), q(g), q(b) }; fwrite(px, 1, 3, f);
        }
        fclose(f);
    }
}
