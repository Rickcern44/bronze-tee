import io
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image
import rasterio
from rasterio.transform import from_origin
from pyproj import Transformer

from tools.course_import import course_import as ci


class CourseImportTests(unittest.TestCase):
    def test_osm_features_keep_polygon_geometry_and_tags(self):
        osm={"elements":[
            {"type":"node","id":1,"lon":-81.0,"lat":41.0},
            {"type":"node","id":2,"lon":-81.01,"lat":41.01},
            {"type":"way","id":10,"nodes":[1,2],"tags":{"golf":"hole","ref":"1"}},
            {"type":"way","id":11,"geometry":[{"lon":-81.0,"lat":41.0},{"lon":-81.0,"lat":41.01},{"lon":-81.01,"lat":41.01}],"tags":{"golf":"green"}},
            {"type":"way","id":12,"nodes":[1,2],"tags":{"highway":"path"}},
        ]}
        features=ci.elements_to_features(osm)
        self.assertEqual([f["type"] for f in features],["hole","green"])
        self.assertEqual(features[0]["coords"],[[-81.0,41.0],[-81.01,41.01]])
        self.assertEqual(features[1]["osm_id"],11)

    def test_distance_transform_returns_euclidean_distance(self):
        mask=np.ones((5,7),dtype=bool); mask[2,3]=False
        distances=ci.distance_transform_edt(mask)
        self.assertEqual(distances[2,3],0)
        self.assertAlmostEqual(distances[0,0],np.sqrt(13))
        self.assertAlmostEqual(distances[2,5],2)

    def test_surface_map_is_deterministic_la_png(self):
        mask=np.zeros((20,24),dtype=np.uint8); mask[5:15,7:19]=3; mask[8:12,10:16]=4
        with tempfile.TemporaryDirectory() as tmp:
            first=Path(tmp)/"one.srf"; second=Path(tmp)/"two.srf"
            ci._save_surface(mask,first); ci._save_surface(mask,second)
            self.assertEqual(first.read_bytes(),second.read_bytes())
            image=Image.open(io.BytesIO(first.read_bytes()))
            self.assertEqual(image.mode,"LA")
            ids=np.asarray(image)[:,:,0]
            self.assertEqual(int(ids[9,12]),4)
            self.assertEqual(int(ids[0,0]),0)

    def test_frame_points_along_negative_local_z(self):
        line=np.array([[10.,20.],[10.,120.]])
        origin,forward,right,length=ci._frame(line)
        local=ci._local(line,origin,forward,right)
        self.assertEqual(length,100)
        np.testing.assert_allclose(local,[[0,0],[0,-100]])
        np.testing.assert_allclose(right,[1,0])

    def test_config_requires_complete_scorecard(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"course.toml"
            p.write_text('id="sample"\nname="Sample"\nkind="real"\n[[holes]]\nnumber=1\npar=4\nyards={white=350}\n')
            with self.assertRaisesRegex(ValueError,"9 or 18"):
                ci.parse_config(p)

    def test_build_repeats_byte_for_byte_from_offline_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); course=root/"sample"; cache=root/"cache"; cache.mkdir()
            crs="EPSG:32617"; tx=Transformer.from_crs(4326,crs,always_xy=True)
            coords=[[-81.8825,41.3137],[-81.8827,41.3165]]
            east,north=tx.transform(*coords[0]); width=1200; height=1200
            dem=cache/"dem.tif"
            with rasterio.open(dem,"w",driver="GTiff",width=width,height=height,count=1,dtype="float32",crs=crs,transform=from_origin(east-600,north+600,1,1),nodata=-9999) as ds:
                ds.write(np.full((height,width),250,dtype=np.float32),1)
            def feature(kind,ident,points,ref=None):
                return {"type":kind,"osm_type":"way","osm_id":ident,"ref":ref,"coords":points,"tags":{}}
            # Small polygons around the mapped endpoints, expressed as lon/lat.
            lon,lat=coords[-1]
            square=[[lon-.00008,lat-.00005],[lon+.00008,lat-.00005],[lon+.00008,lat+.00005],[lon-.00008,lat+.00005]]
            t_lon,t_lat=coords[0]
            tee=[[t_lon-.00004,t_lat-.00003],[t_lon+.00004,t_lat-.00003],[t_lon+.00004,t_lat+.00003],[t_lon-.00004,t_lat+.00003]]
            pin=[[lon,lat]]
            features=[feature("hole",100,coords,"1"),feature("green",101,square),feature("tee",102,tee),feature("pin",103,pin)]
            course.mkdir(); (course/"fetched.json").write_text(__import__("json").dumps({"features":features,"crs":crs,"bbox":[-81.89,41.31,-81.87,41.32],"retrieved":"2026-01-01","dem_product":{}}))
            spec={"id":"sample","name":"Sample","kind":"real","holes":[{"number":1,"par":4,"yards":{"white":350}}]}
            first=ci.build(spec,course,cache)
            first_bytes={p.relative_to(course).as_posix():p.read_bytes() for p in course.rglob("*") if p.is_file()}
            second=ci.build(spec,course,cache)
            second_bytes={p.relative_to(course).as_posix():p.read_bytes() for p in course.rglob("*") if p.is_file()}
            self.assertEqual(first_bytes,second_bytes)
            self.assertEqual(first["holes"],1)
            self.assertEqual(second["warnings"],[])


if __name__=="__main__":
    unittest.main()
