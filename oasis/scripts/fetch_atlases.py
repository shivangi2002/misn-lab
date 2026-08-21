"""
Fetch the four atlases Siddhant asked for and report what each contains.

Harvard-Oxford ships with FSL; the other three come from nilearn, which
downloads them once and caches them.
"""

import os
import numpy as np
import nibabel as nib
from nilearn import datasets

os.makedirs("oasis/atlases", exist_ok=True)

print("=" * 60)

# ---- 1. Harvard-Oxford (from FSL) ----
ho_path = os.path.join(
    os.environ["FSLDIR"],
    "data/atlases/HarvardOxford/HarvardOxford-cort-maxprob-thr25-2mm.nii.gz",
)
ho = nib.load(ho_path)
ho_n = len(np.unique(ho.get_fdata())) - 1        # minus the 0 = "no region"
print(f"Harvard-Oxford  {ho_n:>4} regions   {ho.shape}   (FSL)")

# ---- 2. AAL ----
aal = datasets.fetch_atlas_aal()
aal_img = nib.load(aal.maps)
print(f"AAL             {len(aal.labels):>4} regions   {aal_img.shape}")

# ---- 3. Dosenbach 2010 (coordinates, not a volume) ----
dos = datasets.fetch_coords_dosenbach_2010()
print(f"Dosenbach       {len(dos.rois):>4} regions   COORDINATES, not a volume")

# ---- 4. Craddock 200 ----
cc = datasets.fetch_atlas_craddock_2012()
cc_img = nib.load(cc.scorr_mean)
print(f"Craddock 200    {'?':>4} regions   {cc_img.shape}   (4D: many parcellations)")

print("=" * 60)
print()
print("NOTE ON DOSENBACH: it is a list of 160 sphere CENTRES, not a labelled")
print("volume. Regions are built by drawing spheres of a chosen radius (5mm is")
print("common) around each coordinate. That radius is a parameter to state.")
print()
print("NOTE ON CRADDOCK: the file is 4D - it holds parcellations at many")
print("different region counts. The 200-region one has to be selected from it.")
