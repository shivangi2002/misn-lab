# Lab Notebook — MISN Lab, IIT Delhi

Append-only. Never edit past entries; add corrections as new ones.

## Day 1 — Tue 4 Aug 2026

### Machine
- Windows 11, 12 GB RAM total
- WSL2, Ubuntu 22.04.3, kernel 6.18.33.2
- Raised WSL memory 5.6 GB to 7.8 GB, swap 2 GB to 4 GB via .wslconfig
- Disk: 947 GB free on Linux filesystem

### Installed
- FSL 6.0.7.23 at /home/shivangi/fsl
- FSLeyes 1.20.1
- Python venv misn-env: nibabel, nilearn, numpy, pandas, matplotlib
- git 2.34.1

### Problems and fixes
- Installer reported "Installation failed" twice. Cause was a
  UnicodeDecodeError in its progress-display thread, not the install.
  Attempt 3 succeeded. flirt -version confirmed it worked.
- FSLeyes crashed on launch: "Unable to initialise OpenGL",
  XVisualInfo failure. OpenGL itself was fine (D3D12 / Intel Iris Xe,
  accelerated, max 4.1). Fix: request OpenGL 2.1 instead.
  Made permanent with FSLEYES_GL_VERSION="2 1" in ~/.profile.
  Note the syntax is -gl 2 1, two arguments, not -gl 21.


## Day 2 — Thu 6 Aug 2026
(Day 2 done on 6 Aug; skipped 5 Aug. Plan shifts one day, Day 20 = Tue 1 Sep.)

### Dataset
- OpenNeuro ds002422, "fMRI: resting state and arithmetic task"
- Downloaded sub-01 only: T1w (45 MB), task-rest BOLD (31 MB), BOLD json
- Stored at data/raw/ds002422/sub-01/ in BIDS layout

### Acquisition parameters (from BOLD json sidecar)
- Scanner: Siemens Avanto, 1.5 T
- TR = 3.56 s, TE = 0.05 s, flip angle 90
- Slice thickness 3.6 mm, spacing 3.78 mm, base resolution 64x64
- 36 slices, interleaved (slice timing alternates high/low)
- Phase encoding direction j-
- 3 dummy volumes already discarded by the data providers
- Instructions: eyes closed, stay awake

### Notes
- 1.5 T and TR 3.56 s are both on the slow/low-SNR side vs modern 3 T studies.
  Worth stating in any methods section.
- Interleaved acquisition means slice timing correction is a live question (Day 6).
## Day 3 — Mon 10 Aug (worked Tue 11 Aug) · Skull stripping + segmentation

### Saturday catch-up (completed today)
Block 1 quiz: 7/7 cold, next morning. Block 2 (data concepts) and Block 3 (Paper 1) done.

### The affine
Voxel index (i,j,k) -> physical position in mm from the isocentre.
Ingredients: voxel size (count -> distance), rotation (head is never straight;
also axis swaps and direction flips), offset (where voxel 0,0,0 sits).
One axis, no tilt: position = index x voxel_size + offset.
Why a 3x3 won't do: (a x 0)+(b x 0)+(c x 0) = 0 whatever a,b,c are, so it always
pins voxel 0,0,0 to the isocentre. Offset unpins it. Like "start at floor 5."
Padding: matrices only multiply-and-sum, never plain-add. Pair the offset with a
trailing 1 so it survives into the sum. Bottom row 0 0 0 1 regenerates that 1 so
the answer can feed into a second matrix. Square (not 3x4) so matrices can be
composed and inverted — needed for chaining BOLD -> T1 -> MNI.
Header stores 12 numbers (srow_x/y/z); nibabel adds the 4th row on load.

My T1: 1mm voxels appear OFF-diagonal -> axes reordered + few-degree tilt.
Offset (-91.24, 129.15, -153.46). Voxel (128,128,88) -> (-1.96, -2.21, -37.38) mm.
Near-centre on two axes, as expected — 128 is the middle of 256.

### BET
Ran blind at -f 0.5, then broke it at 0.2 and 0.8.
-f = brightness threshold for "this is brain". Lower keeps more, higher removes more.
  f02 — full brain, but bright knobbly skull/soft tissue left on the left side
  f05 — cleaner, some residue remains at left edge and skull base
  f08 — over-stripped: frontal lobe and superior brain lost
Chose f05. Not 0.2 (too much non-brain), not 0.8 (removed real brain).
Asymmetry worth remembering: leftover skull is visible and fixable later;
removed brain is gone forever. When in doubt, err low.
-R (robust, iterative): no visible improvement on this subject. -R helps most when
there's a lot of neck in the field of view; this scan doesn't have that problem.

### FAST
Bias field = smooth intensity gradient across the image from coil non-uniformity.
Same tissue reads brighter at the centre than at the edge. So white matter at the
edge can match grey matter at the centre — classification by intensity alone fails.
Hence correct the bias field FIRST, then classify.

Ran: fast -B -o derivatives/fast/sub-01 derivatives/bet/sub-01_T1w_brain_f05.nii.gz
Outputs: pve_0 = CSF, pve_1 = grey matter, pve_2 = white matter (partial volume
estimates, 0-1 per voxel, because boundary voxels genuinely contain a mix);
seg/pveseg = hard classification; restore = bias-corrected T1.

All three anatomically sensible:
  pve_2 — solid interior with branching arms, doesn't reach the surface
  pve_1 — thin ribbon tracing every fold; the inverse of pve_2
  pve_0 — ventricles plus a rim around the outside and between folds

QC finding worth keeping: the leftover skull from BET was classified as grey matter
AND as CSF. FAST must assign every voxel to something, so non-brain gets distributed
across the classes. A bad strip propagates downstream silently.

### Done today
GitHub repo created and pushed (was overdue from Sat Block 5).


