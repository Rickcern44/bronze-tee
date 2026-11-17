#!/usr/bin/env python3
"""Crop a USGS 1 m GeoTIFF to a mapped hole. Requires numpy, pyproj, rasterio."""
import argparse
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.windows import Window

# OSM ways 1500889372–1500889375; first and last mapped centerline nodes.
# Local -Z points from mapped tee toward mapped green, +X is player's right.
HOLES = {
    1: ((-81.8824741, 41.3137442), (-81.8827157, 41.3165442), 161, 301),
    2: ((-81.8824036, 41.3169614), (-81.8843399, 41.3177840), 161, 301),
    3: ((-81.8840701, 41.3182091), (-81.8805836, 41.3173350), 161, 301),
    4: ((-81.8800626, 41.3172285), (-81.8823083, 41.3197786), 171, 251),
}
X_MIN, Z_MAX, STEP = -120.0, 100.0, 2.0

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('geotiff')
    parser.add_argument('output')
    parser.add_argument('--hole', type=int, choices=HOLES, default=4)
    args = parser.parse_args()
    tee, green, width, height = HOLES[args.hole]
    with rasterio.open(args.geotiff) as src:
        convert = Transformer.from_crs('EPSG:4326', src.crs, always_xy=True)
        east, north = convert.transform(*tee)
        green_e, green_n = convert.transform(*green)
        forward = np.array([green_e - east, green_n - north])
        forward /= np.linalg.norm(forward)
        right = np.array([forward[1], -forward[0]])
        xx, zz = np.meshgrid(X_MIN + np.arange(width) * STEP, Z_MAX - np.arange(height) * STEP)
        e = east + right[0] * xx - forward[0] * zz
        n = north + right[1] * xx - forward[1] * zz
        cols, rows = (~src.transform) * (e, n)
        # Raster sample locations are pixel centres, not upper-left corners.
        cols, rows = cols - .5, rows - .5
        c0, r0 = int(np.floor(cols.min())) - 1, int(np.floor(rows.min())) - 1
        c1, r1 = int(np.ceil(cols.max())) + 2, int(np.ceil(rows.max())) + 2
        data = src.read(1, window=Window(c0, r0, c1-c0, r1-r0))
        col, row = cols-c0, rows-r0
        ci, ri = np.floor(col).astype(int), np.floor(row).astype(int)
        u, v = col-ci, row-ri
        samples = (data[ri, ci]*(1-u)*(1-v) + data[ri, ci+1]*u*(1-v)
                   + data[ri+1, ci]*(1-u)*v + data[ri+1, ci+1]*u*v)
        if not np.isfinite(samples).all() or (samples < -1000).any():
            raise ValueError('Source has missing elevations in the requested crop')
        # Tee is on-grid. Relative heights avoid depending on the vertical datum.
        reference = float(samples[int(Z_MAX/STEP), int(-X_MIN/STEP)])
        samples = (samples-reference).astype('<f4')
        Path(args.output).write_bytes(samples.tobytes())
        print(f'Hole {args.hole}: {width} x {height}, {STEP:g} m spacing; tee elevation {reference:.3f} m; relative range {samples.min():.2f} to {samples.max():.2f} m')

if __name__ == '__main__':
    main()
