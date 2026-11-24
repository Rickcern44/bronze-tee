#!/usr/bin/env python3
"""Fetch, build and validate a real US golf course from OSM and USGS 3DEP."""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tomllib
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from pyproj import CRS, Transformer
from rasterio.transform import from_bounds

CACHE = Path.home() / ".cache/bronze-tee/courses"
OSM_TAGS = {"hole", "tee", "green", "pin", "fairway", "bunker", "water_hazard", "lateral_water_hazard", "cartpath"}
# .srf channel-0 IDs. The game reads these as enum Surface in scripts/main.gd;
# tests/test_course_import.py fails if the two tables drift apart.
SURFACE = {"deep_rough":0,"second_cut":1,"first_cut":2,"fairway":3,"green":4,"collar":5,"tee":6,"path":7,"water":8,"bunker":9}
SURFACE_SPACING=0.5 # metres between .srf samples
SURFACE_DISTANCE_UNIT=0.1 # metres per channel-1 step; 255 steps clamp at 25.5 m
UA = "BronzeTeeCourseImport/1.0 (course data import; contact project maintainers)"

def request(url: str, payload: bytes | None = None) -> bytes:
    req = urllib.request.Request(url, data=payload, headers={"User-Agent": UA, "Content-Type":"application/x-www-form-urlencoded"} if payload else {"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=90) as response: return response.read()

def distance_transform_edt(mask: np.ndarray) -> np.ndarray:
    """Exact Euclidean distance to the nearest False pixel (separable EDT)."""
    h,w=mask.shape; inf=float((h+h+w+w)**2)
    def transform(f):
        n=len(f)
        if np.all(f>=inf*0.5): return np.full(n,inf,dtype=float)
        v=np.zeros(n,dtype=np.int32); z=np.empty(n+1,dtype=float)
        k=0; v[0]=0; z[0]=-np.inf; z[1]=np.inf
        for q in range(1,n):
            s=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k])
            while s<=z[k]:
                k-=1; s=((f[q]+q*q)-(f[v[k]]+v[k]*v[k]))/(2*q-2*v[k])
            k+=1;v[k]=q;z[k]=s;z[k+1]=np.inf
        out=np.empty(n,dtype=float);k=0
        for q in range(n):
            while z[k+1]<q:k+=1
            out[q]=(q-v[k])**2+f[v[k]]
        return out
    seeds=~mask
    if not seeds.any(): return np.full(mask.shape,math.sqrt(inf),dtype=float)
    f=np.where(seeds,0.0,inf); first=np.empty_like(f)
    for y in range(h): first[y,:]=transform(f[y,:])
    second=np.empty_like(first)
    for x in range(w): second[:,x]=transform(first[:,x])
    return np.sqrt(second)

def parse_config(path: Path) -> dict:
    with path.open("rb") as stream: data = tomllib.load(stream)
    if not data.get("id") or not data.get("name") or data.get("kind") != "real": raise ValueError("course.toml requires id, name and kind = 'real'")
    holes = data.get("holes", [])
    if len(holes) not in (9,18) or sorted(h.get("number",0) for h in holes) != list(range(1,len(holes)+1)): raise ValueError("course.toml must define 9 or 18 uniquely numbered holes")
    if any(not h.get("par") or not h.get("yards") for h in holes): raise ValueError("each hole requires par and scorecard yards")
    return data

def _yards(hole):
    yards=hole["yards"]
    return float(yards.get("white",next(iter(yards.values())))) if isinstance(yards,dict) else float(yards)

def bounds_and_id(spec: dict) -> tuple[tuple[float,float,float,float],str | None]:
    real=spec.get("real", {})
    if "bbox" in real: return tuple(map(float,real["bbox"])), None
    osm=real.get("osm_course","")
    kind, _, ident=osm.partition("/")
    if kind not in ("way","relation") or not ident.isdigit(): raise ValueError("real.osm_course must be way/<id> or relation/<id>, or specify real.bbox")
    data=json.loads(request(f"https://www.openstreetmap.org/api/0.6/{kind}/{ident}.json"))
    obj=data["elements"][0]; b=obj.get("bounds")
    if not b: raise ValueError("OSM course object has no bounds")
    return (b["minlon"],b["minlat"],b["maxlon"],b["maxlat"]), f"{kind}/{ident}"

def osm_query(bbox: tuple[float,float,float,float]) -> dict:
    a,b,c,d=bbox; q=f"[out:json][timeout:60];(nwr[\"golf\"]({b},{a},{d},{c}););out center meta geom;"
    try:
        raw=request("https://overpass-api.de/api/interpreter",q.encode())
    except Exception:
        raw=request("https://api.openstreetmap.org/api/0.6/map.json?bbox="+urllib.parse.quote(f"{a},{b},{c},{d}",safe=","))
    return json.loads(raw)

def elements_to_features(osm: dict) -> list[dict]:
    nodes={e["id"]:(e["lon"],e["lat"]) for e in osm.get("elements",[]) if e["type"]=="node"}
    out=[]
    for e in osm.get("elements",[]):
        tags=e.get("tags",{}); typ=tags.get("golf")
        if typ not in OSM_TAGS: continue
        coords=e.get("geometry") or ([nodes[n] for n in e.get("nodes",[]) if n in nodes])
        if not coords and e.get("center"): coords=[(e["center"]["lon"],e["center"]["lat"])]
        if not coords: continue
        out.append({"osm_type":e["type"],"osm_id":e["id"],"type":typ,"ref":tags.get("ref"),"name":tags.get("name"),"coords":[list(p) for p in coords],"tags":tags})
    return out

def fetch(spec: dict, course_dir: Path) -> dict:
    bbox, osm_id=bounds_and_id(spec); cache=CACHE/spec["id"]; cache.mkdir(parents=True,exist_ok=True)
    raw=osm_query(bbox); osm_path=cache/"osm.json"; osm_path.write_text(json.dumps(raw,sort_keys=True,separators=(",",":")))
    features=elements_to_features(raw)
    crs=CRS.from_epsg(32600+int(( (bbox[0]+bbox[2])/2+180)//6)+1)
    tr=Transformer.from_crs(4326,crs,always_xy=True); corners=[tr.transform(x,y) for x,y in [(bbox[0],bbox[1]),(bbox[2],bbox[3])]]
    margin=40; minx,miny=map(min,zip(*corners)); maxx,maxy=map(max,zip(*corners)); minx-=margin;miny-=margin;maxx+=margin;maxy+=margin
    w=math.ceil(maxx-minx); h=math.ceil(maxy-miny)
    if max(w,h)>8000: raise ValueError("course DEM crop exceeds the 3DEP 8000-pixel side limit")
    url="https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/exportImage?"+urllib.parse.urlencode({"bbox":f"{minx},{miny},{maxx},{maxy}","bboxSR":crs.to_epsg(),"imageSR":crs.to_epsg(),"size":f"{w},{h}","format":"tiff","pixelType":"F32","interpolation":"RSP_BilinearInterpolation","noData":-9999,"f":"image"})
    dem_path=cache/"dem.tif"; dem_path.write_bytes(request(url))
    with rasterio.open(dem_path) as ds:
        resolution=max(abs(ds.transform.a),abs(ds.transform.e)); nodata=ds.nodata
        if resolution>1.05: print(f"WARNING: requested 1 m DEM returned {resolution:.2f} m pixels",file=sys.stderr)
        products_url="https://tnmaccess.nationalmap.gov/api/v1/products?"+urllib.parse.urlencode({"datasets":"Digital Elevation Model (DEM) 1 meter","bbox":f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}","prodFormats":"GeoTIFF"})
        products=json.loads(request(products_url)).get("items",[])
    result={"bbox":bbox,"osm_id":osm_id,"crs":crs.to_string(),"dem_resolution_m":resolution,"dem_nodata":nodata,"dem_product":products[0] if products else None,"retrieved":date.today().isoformat(),"features":features}
    (cache/"manifest.json").write_text(json.dumps(result,indent=2,sort_keys=True)); course_dir.mkdir(parents=True,exist_ok=True)
    (course_dir/"fetched.json").write_text(json.dumps(result,indent=2,sort_keys=True))
    return result

def _line_coords(feature:dict,tr:Transformer)->np.ndarray:
    return np.asarray([tr.transform(*p) for p in feature["coords"]],dtype=float)

def _frame(line:np.ndarray):
    delta=line[-1]-line[0]; length=np.linalg.norm(delta)
    if length<1: raise ValueError("hole centerline is too short")
    forward=delta/length; right=np.array([forward[1],-forward[0]])
    return line[0],forward,right,length

def _local(points,origin,forward,right):
    d=points-origin
    return np.column_stack((d@right,-d@forward))

def _assign(features:list[dict], holes:list[dict], tr:Transformer)->dict[int,list[tuple[str,np.ndarray]]]:
    lines={int(h["number"]):_line_coords(next((f for f in features if f["type"]=="hole" and str(f.get("ref"))==str(h["number"])),{}),tr) for h in holes}
    assigned={int(h["number"]):[] for h in holes}
    for feature in features:
        if feature["type"]=="hole": continue
        pts=_line_coords(feature,tr)
        if not len(pts): continue
        if feature["type"]=="pin": owner=min(lines,key=lambda n:np.linalg.norm(pts[0]-lines[n][-1]))
        elif feature["type"]=="green": owner=min(lines,key=lambda n:np.linalg.norm(pts.mean(axis=0)-lines[n][-1]))
        elif feature["type"]=="tee": owner=min(lines,key=lambda n:np.linalg.norm(pts.mean(axis=0)-lines[n][0]))
        else: owner=min(lines,key=lambda n:min(np.linalg.norm(p-lines[n],axis=1).min() for p in pts[::max(1,len(pts)//20)]))
        assigned[owner].append((feature["type"],pts))
    return assigned

def build(spec:dict, course_dir:Path, cache_dir:Path|None=None)->dict:
    fetched=json.loads((course_dir/"fetched.json").read_text())
    features=fetched["features"]; crs=CRS.from_user_input(fetched["crs"]); tr=Transformer.from_crs(4326,crs,always_xy=True)
    dem=Path(cache_dir or (CACHE/spec["id"])) / "dem.tif"
    if not dem.exists(): raise ValueError(f"missing cached DEM: {dem}; run fetch first")
    assigned=_assign(features,spec["holes"],tr)
    out=course_dir; (out/"holes").mkdir(parents=True,exist_ok=True); (out/"terrain").mkdir(parents=True,exist_ok=True)
    resources=[]; warnings=[]
    for hole in sorted(spec["holes"],key=lambda h:h["number"]):
        num=int(hole["number"]); line_feature=next((f for f in features if f["type"]=="hole" and str(f.get("ref"))==str(num)),None)
        if not line_feature and not hole.get("osm_hole"): raise ValueError(f"hole {num}: no OSM golf=hole ref={num}; set osm_hole or add the way")
        if hole.get("osm_hole"):
            ot,oi=hole["osm_hole"].split("/"); line_feature=next(f for f in features if f["osm_type"]==ot and str(f["osm_id"])==oi)
        line=_line_coords(line_feature,tr); origin,forward,right,length=_frame(line)
        local=_local(line,origin,forward,right); line_xz=[[round(float(x),3),round(float(z),3)] for x,z in local]
        assigned_features=assigned[num]
        greens=[_local(p,origin,forward,right) for typ,p in assigned_features if typ=="green"]
        tees=[_local(p,origin,forward,right).mean(axis=0) for typ,p in assigned_features if typ=="tee"]
        pins=[_local(p,origin,forward,right)[0] for typ,p in assigned_features if typ=="pin"]
        if not greens: warnings.append(f"hole {num}: no assigned green")
        if not tees: warnings.append(f"hole {num}: no assigned tee")
        pin=pins[0] if pins else local[-1]
        if greens and not any(_point_in_poly(pin,g) for g in greens): warnings.append(f"hole {num}: pin outside assigned green")
        yards=_yards(hole)
        if yards>0 and abs(length-yards*0.9144)>0.1*yards*0.9144: warnings.append(f"hole {num}: mapped line {length:.1f} m differs from scorecard by >10%")
        minz=min(-length-40,-50); maxz=40; minx=-70; maxx=70; step=2
        for typ,points in assigned_features:
            local_feature=_local(points,origin,forward,right)
            if np.any(local_feature[:,0]<minx) or np.any(local_feature[:,0]>maxx) or np.any(local_feature[:,1]<minz) or np.any(local_feature[:,1]>maxz): warnings.append(f"hole {num}: {typ} extends beyond the 40 m terrain margin")
        surface_features=[]
        for feature in features:
            typ=feature["type"]
            if typ in {"hole","pin"}: continue
            points=_line_coords(feature,tr); local_feature=_local(points,origin,forward,right)
            overlaps=(local_feature[:,0].min()<=maxx and local_feature[:,0].max()>=minx and local_feature[:,1].min()<=maxz and local_feature[:,1].max()>=minz)
            if not overlaps: continue
            owner_has=any(ftype==typ and np.array_equal(fpoints,points) for ftype,fpoints in assigned_features)
            # Adjacent greens and tee pads are playable fairway from this hole.
            if owner_has: surface_features.append((typ,points))
            elif typ in {"green","tee"}: surface_features.append(("fairway",points))
            elif typ in {"fairway","bunker","water_hazard","lateral_water_hazard","cartpath"}: surface_features.append((typ,points))
        nx=math.ceil((maxx-minx)/step)+1; nz=math.ceil((maxz-minz)/step)+1
        xx,zz=np.meshgrid(minx+np.arange(nx)*step,maxz-np.arange(nz)*step)
        east=origin[0]+right[0]*xx-forward[0]*zz; north=origin[1]+right[1]*xx-forward[1]*zz
        with rasterio.open(dem) as ds:
            cols,rows=(~ds.transform)*(east,north); cols-=.5;rows-=.5
            c0,r0=max(0,int(cols.min())-1),max(0,int(rows.min())-1); c1,r1=min(ds.width,int(cols.max())+2),min(ds.height,int(rows.max())+2)
            arr=ds.read(1,window=rasterio.windows.Window(c0,r0,c1-c0,r1-r0)).astype(float)
            col,row=cols-c0,rows-r0; ci,ri=np.floor(col).astype(int),np.floor(row).astype(int); u,v=col-ci,row-ri
            if arr.shape[0]<2 or arr.shape[1]<2 or np.any(ci<0) or np.any(ri<0) or np.any(ci+1>=arr.shape[1]) or np.any(ri+1>=arr.shape[0]): raise ValueError(f"hole {num}: DEM does not cover crop plus 40 m margin")
            heights=arr[ri,ci]*(1-u)*(1-v)+arr[ri,ci+1]*u*(1-v)+arr[ri+1,ci]*(1-u)*v+arr[ri+1,ci+1]*u*v
            if not np.isfinite(heights).all() or (ds.nodata is not None and np.any(heights==ds.nodata)): raise ValueError(f"hole {num}: DEM crop contains nodata")
        reference=float(heights[np.abs(zz).argmin(axis=0)[np.abs(xx[0]).argmin()],np.abs(xx[0]).argmin()])
        heights=(heights-reference).astype("<f4")
        terrain_path=out/"terrain"/f"hole_{num:02d}.f32"; terrain_path.write_bytes(heights.tobytes(order="C"))
        sxx,szz=np.meshgrid(minx+np.arange(math.ceil((maxx-minx)/SURFACE_SPACING)+1)*SURFACE_SPACING,maxz-np.arange(math.ceil((maxz-minz)/SURFACE_SPACING)+1)*SURFACE_SPACING)
        surface=_raster_surfaces(num,hole,surface_features,line,origin,forward,right,sxx,szz)
        srf_path=out/"terrain"/f"hole_{num:02d}.srf"; _save_surface(surface,srf_path)
        green_poly=next((g for g in greens if len(g)>=3),None)
        green_center=green_poly.mean(axis=0) if green_poly is not None else pin
        if green_poly is None: green_radii=[16.0,15.0]
        else: green_radii=[max(2,float(np.ptp(green_poly[:,0])/2)),max(2,float(np.ptp(green_poly[:,1])/2))]
        latlon=[float(x) for x in line_feature["coords"][0]]
        hole_path=out/"holes"/f"hole_{num:02d}.tres"
        hole["course_id"]=spec["id"]
        hole_res=_hole_resource(num,hole,line_xz,local,pin,green_center,green_radii,tees,latlon,step,srf_path,terrain_path,surface.shape,(nx,nz),minz,maxz)
        hole_path.write_text(hole_res)
        resources.append(hole_path.relative_to(out).as_posix())
    _write_course(spec,out,resources,fetched)
    _write_attribution(spec,out,fetched)
    result={"warnings":warnings,"holes":len(resources),"resources":resources}
    (out/"build_report.json").write_text(json.dumps(result,indent=2,sort_keys=True)+"\n")
    return result

def _point_in_poly(p,poly):
    inside=False; x,y=p
    for i in range(len(poly)):
        x1,y1=poly[i];x2,y2=poly[(i+1)%len(poly)]
        if (y1>y)!=(y2>y) and x<(x2-x1)*(y-y1)/(y2-y1)+x1: inside=not inside
    return inside

def _raster_surfaces(num,hole,features,line,origin,forward,right,xx,zz):
    S=SURFACE; deep=S["deep_rough"]
    surface=np.full(xx.shape,deep,dtype=np.uint8); xz=_local(line,origin,forward,right)
    feature_ids={"green":S["green"],"fairway":S["fairway"],"tee":S["tee"],"bunker":S["bunker"],"water_hazard":S["water"],"lateral_water_hazard":S["water"],"cartpath":S["path"]}
    # Polygon masks are evaluated in the feature's own frame.
    for typ,pts in features:
        if typ not in feature_ids: continue
        poly=_local(pts,origin,forward,right)
        if len(poly)<3: continue
        mask=_polygon_mask(xx,zz,poly)
        surface[mask]=feature_ids[typ]
        if typ=="green":
            dilated=distance_transform_edt(~mask)*SURFACE_SPACING<=3
            surface[dilated & ~mask & (surface==deep)]=S["collar"]
    # Generate fairway/cut bands around route where OSM polygon is absent.
    dist=np.full(xx.shape,np.inf)
    for a,b in zip(xz[:-1],xz[1:]):
        vx, vz=b-a; den=vx*vx+vz*vz
        t=np.clip(((xx-a[0])*vx+(zz-a[1])*vz)/max(den,1e-9),0,1)
        dist=np.minimum(dist,np.hypot(xx-(a[0]+t*vx),zz-(a[1]+t*vz)))
    base=surface==deep; surface[base & (dist<16)]=S["fairway"]; surface[(surface==deep)&(dist<20)]=S["first_cut"]; surface[(surface==deep)&(dist<26)]=S["second_cut"]
    # First/second cut around explicit fairways.
    fw=surface==S["fairway"]; near=distance_transform_edt(~fw)*SURFACE_SPACING
    surface[(surface==deep)&(near<=3)]=S["first_cut"]; surface[(surface==deep)&(near<=9)]=S["second_cut"]
    return surface

def _polygon_mask(x,z,poly):
    m=np.zeros(x.shape,dtype=bool)
    for i in range(len(poly)):
        x1,y1=poly[i];x2,y2=poly[(i+1)%len(poly)]
        crosses=((y1>z)!=(y2>z)) & (x<(x2-x1)*(z-y1)/(y2-y1+1e-30)+x1)
        m ^= crosses
    return m

def _surface_bytes(surface:np.ndarray)->np.ndarray:
    """Pack IDs and boundary distances as the (rows, cols, 2) uint8 .srf payload.

    Channel 0 (PNG luminance) is the surface ID. Channel 1 (PNG alpha) is the
    distance from the sample to the nearest boundary with a different surface,
    in 0.1 m units clamped at 255. The boundary lies halfway between two
    differing samples, so a sample next to one is 0.25 m from it.
    """
    surface=np.asarray(surface,dtype=np.uint8)
    edge=np.full(surface.shape,np.inf,dtype=float)
    for sid in np.unique(surface):
        mask=surface==sid
        edge[mask]=np.minimum(edge[mask],distance_transform_edt(mask)[mask])
    # Units per sample, rounded so 0.5/0.1 is exactly 5 and halves round up.
    units=round(SURFACE_SPACING/SURFACE_DISTANCE_UNIT,6)
    distance=np.clip(np.floor(np.maximum(edge-0.5,0.0)*units+0.5),0,255).astype(np.uint8)
    return np.dstack((surface,distance))

def _save_surface(surface,path):
    # Shape (rows, cols, 2) uint8 is written as an 8-bit grayscale+alpha (LA) PNG.
    image=Image.fromarray(_surface_bytes(surface))
    if image.mode!="LA": raise ValueError(f"surface map encoded as {image.mode}, expected LA")
    import io
    buf=io.BytesIO(); image.save(buf,format="PNG",optimize=False); path.write_bytes(buf.getvalue())

def _hole_resource(num,hole,line_xz,line,pin,green_center,green_radii,tees,latlon,step,srf_path,terrain_path,dims,elevation_dims,minz,maxz):
    # Emit contract properties even when this checkout's RCE-168/169 Resource classes are not yet landed.
    origin=[round(float(latlon[0]),8),round(float(latlon[1]),8)]
    center=[round(float(green_center[0]),3),round(float(green_center[1]),3)]
    pads=sorted(tees,key=lambda p:np.linalg.norm(p[0]))
    white=pads[0] if pads else np.array([0.,0.]); extras=pads[1:]
    def v2(p): return f"Vector2({float(p[0]):.3f}, {float(p[1]):.3f})"
    def arr(vs): return "Array[Vector2](["+", ".join(v2(p) for p in vs)+"])"
    # Surface origin follows the top-left sample (min X, max Z).
    text='[gd_resource type="Resource" script_class="HoleDefinition" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/course/hole_definition.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\n'
    course_id=hole["course_id"]
    yardages=hole["yards"] if isinstance(hole["yards"],dict) else {"white":hole["yards"]}
    attrs={"number":str(num),"display_name":f'"Hole {num}"',"par":str(int(hole["par"])),"yards":str(_yards(hole)),"tee_position":v2(white),"cup_position":v2(pin),"blue_tee_offset":v2(extras[0]-white) if extras else "Vector2.ZERO","black_tee_offset":v2(extras[1]-white) if len(extras)>1 else "Vector2.ZERO","blue_tee_yards":str(float(yardages.get("blue",0))),"black_tee_yards":str(float(yardages.get("black",0))),"green_radii":f"Vector2({green_radii[0]:.3f}, {green_radii[1]:.3f})","fairway_centerline":arr(line_xz),"elevation_file":f'"res://resources/courses/{course_id}/terrain/hole_{num:02d}.f32"',"elevation_origin":"Vector2(-70.000, 40.000)","elevation_spacing":"2.0","elevation_dimensions":f"Vector2i({elevation_dims[0]}, {elevation_dims[1]})","origin_latlon":v2(origin),"bearing_deg":str(math.degrees(math.atan2(line[-1,0]-line[0,0],line[-1,1]-line[0,1]))),"surface_map_file":f'"res://resources/courses/{course_id}/terrain/hole_{num:02d}.srf"',"surface_map_origin":"Vector2(-70.000, 40.000)","surface_map_spacing":str(SURFACE_SPACING),"surface_map_dimensions":f"Vector2i({int(dims[1])}, {int(dims[0])})"}
    for key,value in attrs.items(): text+=f"{key} = {value}\n"
    return text

def _write_course(spec,out,resources,fetched):
    refs=", ".join(f'ExtResource("{i+1}")' for i in range(len(resources)))
    ext="".join(f'[ext_resource type="Resource" path="res://resources/courses/{spec["id"]}/{p}" id="{i+1}"]\n' for i,p in enumerate(resources))
    product=fetched.get("dem_product") or {}
    provenance=[{"name":product.get("title","USGS 3DEP 1 meter DEM"),"url":product.get("downloadURL","https://www.usgs.gov/3d-elevation-program"),"license":"Public domain","attribution":"USGS 3D Elevation Program","retrieved":fetched["retrieved"],"survey_date":product.get("publicationDate",product.get("dateCreated","unknown"))},{"name":"OpenStreetMap","url":"https://www.openstreetmap.org/copyright","license":"ODbL","attribution":"© OpenStreetMap contributors","retrieved":fetched["retrieved"],"survey_date":"unknown"}]
    provenance_gd="Array[Dictionary](["+", ".join("{ "+", ".join(f'{json.dumps(k)}: {json.dumps(str(v))}' for k,v in item.items())+" }" for item in provenance)+"])"
    centroid=[(fetched["bbox"][0]+fetched["bbox"][2])/2,(fetched["bbox"][1]+fetched["bbox"][3])/2]
    crs=CRS.from_user_input(fetched["crs"])
    text=f'[gd_resource type="Resource" script_class="CourseDefinition" load_steps={len(resources)+2} format=3]\n\n[ext_resource type="Script" path="res://scripts/course/course_definition.gd" id="script"]\n{ext}\n[resource]\nscript = ExtResource("script")\nid = {json.dumps(spec["id"])}\nsource_kind = "real"\nprovenance = {provenance_gd}\ncrs = {json.dumps(crs.to_string())}\norigin_latlon = Vector2({centroid[0]:.8f}, {centroid[1]:.8f})\nnotes = "Generated by tools/course_import"\ndisplay_name = {json.dumps(spec["name"])}\nholes = Array[Resource]([{refs}])\n'
    (out/"course.tres").write_text(text)

def _write_attribution(spec,out,fetched):
    product=fetched.get("dem_product") or {}; name=product.get("title","USGS 3DEP 1 meter DEM"); survey=product.get("publicationDate",product.get("dateCreated","unknown"))
    (out/"ATTRIBUTION.md").write_text(f'''# {spec['name']} data attribution\n\n- Elevation: {name}. USGS 3D Elevation Program; public domain. Retrieved {fetched['retrieved']}; survey/product date: {survey}.\n- Golf features: OpenStreetMap contributors, © OpenStreetMap contributors, licensed under [ODbL](https://www.openstreetmap.org/copyright). Retrieved {fetched['retrieved']}.\n\nThis course data is derived from these sources.\n''')

def validate(spec:dict,course_dir:Path,build_result:dict|None=None)->list[str]:
    errors=[]; holes=spec["holes"]
    if len(holes) not in (9,18): errors.append("course must have 9 or 18 holes")
    for h in holes:
        n=h["number"]
        for ext in ("f32","srf"):
            p=course_dir/"terrain"/f"hole_{n:02d}.{ext}"
            if not p.exists(): errors.append(f"hole {n}: missing {p.name}"); continue
            if p.stat().st_size>4*1024*1024: errors.append(f"hole {n}: {p.name} exceeds 4 MiB budget")
            if ext=="f32" and p.stat().st_size%4: errors.append(f"hole {n}: malformed float32 terrain")
            if ext=="srf":
                try:
                    import io
                    im=Image.open(io.BytesIO(p.read_bytes()))
                    if im.mode!="LA": errors.append(f"hole {n}: surface map must be LA PNG")
                except Exception as e: errors.append(f"hole {n}: invalid surface map ({e})")
        if not (course_dir/"holes"/f"hole_{n:02d}.tres").exists(): errors.append(f"hole {n}: missing resource")
    for p in (course_dir/"course.tres",course_dir/"ATTRIBUTION.md"):
        if not p.exists(): errors.append(f"missing {p.name}")
    if build_result is None and (course_dir/"build_report.json").exists():
        build_result=json.loads((course_dir/"build_report.json").read_text())
    if build_result:
        for warning in build_result.get("warnings",[]): errors.append(warning)
    return errors

def preview(spec,course_dir,outdir):
    import io
    outdir.mkdir(parents=True,exist_ok=True); colors=[(30,89,42),(111,126,68),(124,170,88),(74,145,65),(36,132,57),(154,174,88),(210,184,91),(180,171,137),(35,113,166),(183,153,103)]
    thumbs=[]
    for h in spec["holes"]:
        p=course_dir/"terrain"/f"hole_{h['number']:02d}.srf"
        if not p.exists(): continue
        a=np.asarray(Image.open(p).convert("L")); rgb=np.asarray([colors[int(i)%len(colors)] for i in a.flat],dtype=np.uint8).reshape((*a.shape,3))
        im=Image.fromarray(rgb).resize((280,360)); d=ImageDraw.Draw(im); d.text((8,8),f"Hole {h['number']} • {_yards(h):g} yd",fill="white",stroke_width=2,stroke_fill="black")
        im.save(outdir/f"hole_{h['number']:02d}.png"); thumbs.append(im)
    if len(thumbs)==18:
        sheet=Image.new("RGB",(280*6,360*3),(20,20,20))
        for i,im in enumerate(thumbs): sheet.paste(im,((i%6)*280,(i//6)*360))
        sheet.save(outdir/"contact_sheet.png")

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument("command",choices=("init","fetch","build","validate","preview")); parser.add_argument("course_id"); parser.add_argument("--osm"); parser.add_argument("--bbox",nargs=4,type=float,metavar=("MINLON","MINLAT","MAXLON","MAXLAT")); parser.add_argument("--root",type=Path,default=Path("resources/courses")); parser.add_argument("--output",type=Path,default=Path("build/course_import")); args=parser.parse_args(argv)
    try:
        course_dir=args.root/args.course_id; toml=course_dir/"course.toml"
        if args.command=="init":
            if bool(args.osm)==bool(args.bbox): raise ValueError("init requires exactly one of --osm way/id or --bbox minlon minlat maxlon maxlat")
            spec={"id":args.course_id,"name":args.course_id.replace("_"," ").title(),"kind":"real","real":({"osm_course":args.osm} if args.osm else {"bbox":args.bbox}),"scorecard":{"tees":["white"]}}
            bbox,_=bounds_and_id(spec) if args.osm else (args.bbox,None); raw=osm_query(bbox); features=elements_to_features(raw)
            holes=[]
            refs=sorted({int(f["ref"]) for f in features if f["type"]=="hole" and str(f.get("ref","")).isdigit()})
            for n in refs: holes.append({"number":n,"par":4,"handicap":n,"yards":{"white":0}})
            spec["holes"]=holes; course_dir.mkdir(parents=True,exist_ok=True)
            lines=[f'id = "{spec["id"]}"',f'name = "{spec["name"]}"','kind = "real"','', '[real]']
            if args.osm: lines.append(f'osm_course = "{args.osm}"')
            else: lines.append('bbox = ['+', '.join(str(v) for v in args.bbox)+']')
            counts={typ:sum(1 for feature in features if feature["type"]==typ) for typ in sorted(OSM_TAGS)}
            lines.extend(['','[scorecard]','source = ""','tees = ["white"]','','[discovery.feature_counts]'])
            lines.extend(f'{typ} = {count}' for typ,count in counts.items())
            for h in holes: lines.extend(['','[[holes]]',f'number = {h["number"]}',f'par = {h["par"]}',f'handicap = {h["handicap"]}',f'yards = {{ white = 0 }}'])
            toml.write_text('\n'.join(lines)+'\n'); print(f"Wrote draft {toml} with {len(holes)} discovered hole refs and {len(features)} golf features; fill scorecard fields.")
        else:
            spec=parse_config(toml)
            if args.command=="fetch": result=fetch(spec,course_dir); print(f"Fetched {len(result['features'])} golf features; DEM resolution {result['dem_resolution_m']:.2f} m")
            elif args.command=="build":
                result=build(spec,course_dir)
                for w in result["warnings"]: print("WARNING: "+w,file=sys.stderr)
                print(f"Built {result['holes']} holes in {course_dir}")
            elif args.command=="validate":
                errors=validate(spec,course_dir)
                for e in errors: print("ERROR: "+e,file=sys.stderr)
                if errors: return 1
                print(f"Valid: {len(spec['holes'])} holes")
            elif args.command=="preview": preview(spec,course_dir,args.output/args.course_id); print(f"Preview images: {args.output/args.course_id}")
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}",file=sys.stderr); return 1

if __name__=="__main__": raise SystemExit(main())
