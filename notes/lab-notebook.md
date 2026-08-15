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


## Structural pipeline — raw T1 to MNI space

1. BET — remove skull, scalp, neck. `bet T1 T1_brain -f 0.5`
   -f is the brightness threshold. Ran 0.2, 0.5, 0.8 and compared:
   0.2 left non-brain attached, 0.8 cut into frontal lobe. Chose 0.5.
   Must come first: registration would otherwise match skull to skull,
   and segmentation would classify scalp as a tissue type.

2. FAST — bias correction + segmentation. `fast -B -o out T1_brain`
   Bias field = smooth intensity gradient from coil non-uniformity, so the
   same tissue reads brighter in the centre than at the edge. Corrected FIRST,
   because classification by brightness fails on uncorrected data.
   Outputs pve_0 CSF, pve_1 grey matter, pve_2 white matter.

3. FLIRT — linear registration to MNI152. `flirt -dof 12 -omat ...`
   Ran 6 DOF (translation + rotation) and 12 DOF (+ scaling + shear).
   My brain needed a 22% stretch on one axis, so 6 DOF couldn't fit;
   12 DOF closed most of the gap.

4. FNIRT — non-linear registration. `fnirt --aff=12dof.mat ...`
   FLIRT is one transformation for the whole image. FNIRT uses a grid of
   control points (mine: 21x24x21 at 5mm, ~10,600 points x 3 numbers) so
   different regions move differently. Needs FLIRT's output as a starting point.
   Small further improvement at the edges.

5. fsl_anat — the whole thing automated, for comparison.
   Same steps, different order: it registers first, then extracts the brain
   using the warp instead of a brightness threshold. Also reorients and crops,
   which I skipped.
   My brain volume 1494 cm3 vs its 1335 cm3 — mine kept 12% more, consistent
   with the residue I found.

**QC finding:** BET left non-brain fragments at the left edge. They persisted
through FAST (classified as grey matter) and through registration into MNI
space. Errors propagate; later steps don't clean them up.

**Note:** the affine wasn't something I created — it's in the NIfTI header,
written by the scanner. I read it. The FLIRT .mat files are different: those
are transformations I generated, which happen to share the 4x4 format.

## Day 5 — Motion, slice timing, coregistration (13 Aug)
 
Functional preprocessing. Raw BOLD in, MNI-space BOLD out.
 
### Order and why
1. Motion correction
2. Slice timing
3. Coregistration to T1
4. Concatenate to MNI
Motion first because slice timing interpolates in TIME and assumes a voxel
holds the same tissue across volumes — if the head moved, it doesn't.
Coregistration last because it uses one representative volume from the
already-cleaned data.
 
### 1. mcflirt — motion correction
 
```
mcflirt -in <raw bold> -out derivatives/mcflirt/sub-01_bold_mc -plots -report
```
 
Aligns all 200 volumes to a reference using **6 DOF**. Same head throughout,
so nothing should be resized or sheared — only translation and rotation. If
motion correction ever scaled a volume, that would be wrong by construction.
 
**Why motion is so dangerous in fMRI:** the head shifts, so a voxel index now
sits over different tissue. This happens to EVERY voxel at once, so every
region's value changes at the same moment. Correlation then reads "these
regions rise and fall together" as connectivity — when it was a swallow.
Motion doesn't add random noise; it manufactures shared signal, which is
exactly what connectivity analysis is built to detect.
 
Worse, it's systematic: children, older adults and patient groups move more.
So "group X has different connectivity" can just mean "group X moved more."
 
### 2. Framewise displacement
 
`.par` file = 200 rows x 6 columns. Cols 1-3 rotations (radians), 4-6
translations (mm). FSL convention: rotations first.
 
Read off the plots:
 
| | x | y | z |
|---|---|---|---|
| rotations (rad) | 0.004 | 0.002 | **0.008** |
| translations (mm) | **0.405** | 0.265 | 0.365 |
 
z rotation drifts steadily upward — the head settling into the headrest.
x rotation wanders with big dips, no net trend. Different patterns, and the
distinction matters: drift is slow (very low frequency) and gets removed by
the Day 6 high-pass filter. Wander sits closer to the 0.01-0.1 Hz signal band
and can't be filtered out without losing signal.
 
Both lines carry jitter at every timepoint — the difference is only that z's
slow component goes somewhere over the scan and x's doesn't.
 
**Converting rotations to mm:** an angle isn't comparable to a distance, so
rotations get converted using an assumed 50 mm brain radius (Power et al.
2012). distance = radians x 50. My worst: 0.008 x 50 = 0.4 mm.
Methods-section phrasing: *"Rotational parameters were converted to
millimetres assuming a 50 mm brain radius."*
 
Why a radius is needed at all: rotating the head moves a point at the centre
almost not at all, and a point at the outer surface a long way. Distance
travelled depends on radius. 50 mm is a convention (roughly centre-of-brain to
cortex), same for everyone regardless of actual head size — which is what
makes values comparable across studies.
 
**FD formula:** for each consecutive pair of volumes, subtract the six
parameters, convert rotations to mm, take absolute values, sum all six.
Sum not average — averaging would dilute one big movement across five small
ones. Direction doesn't matter, only distance, hence absolute values.
200 volumes -> 199 FD values (volume 1 has no predecessor).
 
```python
par = np.loadtxt(".../sub-01_bold_mc.par")       # (200, 6)
diff = np.diff(par, axis=0)                      # (199, 6)
diff[:, 0:3] = diff[:, 0:3] * 50                 # rotations -> mm
fd = np.abs(diff).sum(axis=1)                    # (199,)
```
 
**Result: mean FD 0.087 mm, max 0.213 mm, 0 volumes above 0.5 mm.**
Very still subject. Nothing to censor, subject not excluded.
 
Common thresholds: 0.5 mm per volume for censoring; mean FD above 0.2-0.3 mm
for excluding a subject entirely. My worst single volume is under half the
censoring threshold.
 
**Why 0.5 mm is the threshold:** empirical, not derived. Power et al. looked
at real data and found correlations became measurably contaminated above it.
There's no geometric cutoff — ANY motion changes a voxel's tissue mix and so
changes its value. A voxel sitting on a grey/white boundary shifts its mix at
any displacement, however small. The question is only whether that change is
small relative to the ~1% BOLD signal.
 
**Second reference point, needs no literature:** compare motion to voxel size.
0.405 / 3.59 = 11% of a voxel. Small. This works on any dataset.
 
**Mistake caught:** I compared 0.405 mm (one axis, total drift over 12 min)
against the 0.5 mm threshold (all six axes, between consecutive volumes).
Not comparable quantities. The per-axis reading is a screening glance and a
diagnostic tool — FD is the number with the threshold attached.
 
**When axis matters and when it doesn't:** screening ("is there a problem at
all?") — take the max across all six, ignore axis. Reporting or diagnosing —
axis matters, because motion on different axes adds up, and because the
pattern can point at a cause. Use FD for the former.
 
### 3. slicetimer — slice timing correction
 
```
slicetimer -i <motion-corrected> -o derivatives/slicetimer/sub-01_bold_st \
           --tcustom=derivatives/mcflirt/slicetiming.txt -r 3.56
```
 
**The problem:** 36 slices are captured one at a time across the 3.56 s TR,
not simultaneously. Slice 1 early in each volume, slice 36 late. That offset
repeats identically in every volume — so two regions in different slices sit
on permanently offset clocks. Correlation receives two bare lists of numbers
with no timestamps attached, pairs them by position, and assumes reading 1
means the same instant in both. It doesn't.
 
Knowing the timestamps doesn't help: sorting tells you WHEN each slice was
captured, it doesn't give you the VALUE at the moment you need.
 
**The fix:** each slice has 200 measurements of its own. The reference time
falls BETWEEN two of them, so interpolate — weight the neighbours by distance
in time. Same idea as FNIRT's control points, one dimension instead of three.
FSL uses the middle slice as reference by default, which minimises how far
anything has to shift.
 
Caveat: interpolation is an estimate, not the truth. It slightly smooths the
time series, and works best when the signal changes slowly relative to TR.
BOLD does, which is why this is acceptable.
 
**Interleaved acquisition:** my SliceTiming alternates high/low
(1.5375, 0, 1.6225, 0.085...) — odd slices first, then even. The scanner does
this because exciting one slice bleeds energy into its immediate neighbours;
leaving a gap lets each recover. Consequence: slices 1 and 2 are NEXT TO EACH
OTHER in space but ~1.5 s apart in time.
 
Used `--tcustom` with the exact JSON values rather than assuming a standard
interleave pattern. slicetimer wants FRACTIONS OF A TR, so divided each by
3.56 — all values then fall between 0 and 1, as they must.
 
Output grew 30M -> 99M and became FLOAT32. Not an error: interpolation
produces distinct fractional values where the input had repeated integers, so
it compresses far less well. Dimensions unchanged, 64x64x36x200.
 
### 4. epi_reg — BOLD to T1 (BBR)
 
```
fslroi <slice-timed> derivatives/epi_reg/sub-01_bold_ref.nii.gz 100 1
epi_reg --epi=<ref> --t1=<whole head> --t1brain=<stripped> --out=...
```
 
Extracted volume 100 (the middle) because epi_reg needs 3D, not 4D. The middle
because motion correction aligned everything near there, so it's
representative rather than an extreme.
 
**Why coregister at all:** BOLD is a blurry 3.59 mm grid. A signal at voxel
(32,32,18) has no anatomical address without the T1. It's also the route into
MNI space.
 
**Two things make it harder than Day 4's registrations:**
 
- Different modalities — T1 and BOLD order tissue brightness differently, so
  subtraction fails as a cost function. Needs mutual information, or BBR.
- The BOLD is genuinely distorted (see below).
**BBR — why the white/grey boundary, not the outer edge:**
 
- The outer edge is BLURRY in BOLD. At 3.59 mm a surface voxel contains grey
  matter + CSF + skull mixed. A smeared band several mm wide, not a step.
  Align to which part of it?
- The outer edge only constrains the RIM. The starfish intuition — fix the
  outline and the inside follows — holds for a RIGID object. BOLD isn't rigid:
  warped near the sinuses, fine elsewhere. So the rim can fit perfectly while
  the interior sits wrong, with no warning.
- The white/grey boundary is sharp in both images (every voxel there is cleanly
  one tissue or the other), follows every fold so landmarks are spread
  THROUGHOUT the volume, and survives distortion — BBR asks "does the BOLD have
  an edge where the T1 says there should be one?", not "are these values
  equal?"
Note white matter is the solid INTERIOR mass, not the outer surface — the
boundary is the interface between white and grey, deep inside, following every
fold.
 
Log showed: FAST segmentation -> FLIRT pre-alignment -> BBR. Same
coarse-then-refine pattern as FLIRT -> FNIRT. The boundary comes from FAST,
so Day 3's segmentation feeds directly into functional coregistration.
 
**Final cost 0.454** (lower is better; under ~0.6 is good).
Matrix: diagonal all ~1.0, off-diagonal ~0 — no rotation, no scaling, as
6 DOF requires. Translations only, about -1.1 / 3.7 / -1.7 mm.
 
### 5. Concatenation to MNI
 
```
convert_xfm -omat bold2mni.mat -concat T1_to_MNI_12dof.mat sub-01_bold2t1.mat
flirt -in <bold ref> -ref MNI152_T1_2mm_brain -applyxfm -init bold2mni.mat -out ...
```
 
Two 4x4 matrices multiplied into one. `-concat` reads right to left.
This is exactly why the affine is 4x4 and not 3x3 (Day 3): square matrices
compose. `-applyxfm` means don't search, just apply the matrix given.
 
QC: BOLD sits inside the template outline in all three views; ventricles line
up with the template's ventricles.
 
### Distortion — NOT corrected, a stated limitation
 
EPI (Echo-Planar Imaging) grabs a whole slice in ~100 ms, which is what makes
200 volumes in 12 minutes possible. It's also why BOLD voxels are coarse
(3.59 mm) and the image looks blurry next to the T1.
 
The cost: EPI locates each signal by its frequency, which assumes a uniform
magnetic field.
 
The field isn't uniform. Air and tissue have different MAGNETIC SUSCEPTIBILITY
(how much a material distorts a field passing through it — an electron-
structure property, NOT about proton count; the scanner's magnet creates the
field regardless of what's inside it). At air/tissue boundaries — sinuses, ear
canals — the field bends. Signals from there return at slightly wrong
frequencies, so EPI places the tissue in the wrong location: stretching,
squashing, and signal dropout, along the phase-encoding direction (`j-` in my
JSON).
 
**The fix is a fieldmap — a separate scan acquired in the same session, which
measures how the field actually varies. My dataset has none, so this CANNOT be
corrected.** Not reconstructable after the fact.
 
What to do instead: state it as a limitation, use BBR (more robust to
distortion than intensity-based methods), and treat orbitofrontal and inferior
temporal regions as least reliable in this data.
 
### QC finding — the residue, fourth appearance
 
The skull fragments BET left at -f 0.5 have now shown up in: FAST (classified
as grey matter), the MNI-registered T1, the fsl_anat volume comparison
(mine 12% larger), and now epi_reg — it ran its own FAST on my stripped brain,
so the residue produced a spurious boundary fragment outside the brain,
visible in qc/epi_reg_bbr2.png.
 
Not fixed. The boundary is dominated by thousands of correct points, cost is
good, alignment is visibly good. Could re-run with fsl_anat's
T1_biascorr_brain if it ever matters.
 
**The lesson, four times over: errors propagate. Later steps don't clean them
up, they carry them forward.**
 
### Day 5 outputs
 
```
derivatives/mcflirt/sub-01_bold_mc.nii.gz    motion-corrected 4D
derivatives/mcflirt/sub-01_bold_mc.par       6 params x 200 volumes
derivatives/mcflirt/sub-01_fd.txt            199 FD values
derivatives/mcflirt/slicetiming.txt          36 timings, fractions of TR
derivatives/slicetimer/sub-01_bold_st.nii.gz slice-timing corrected
derivatives/epi_reg/sub-01_bold2t1.mat       BOLD -> T1
derivatives/epi_reg/bold2mni.mat             BOLD -> MNI (concatenated)
derivatives/epi_reg/sub-01_bold_mni.nii.gz   BOLD in MNI space
qc/motion_rot.png, qc/motion_trans.png
qc/epi_reg_bbr.png, qc/epi_reg_bbr2.png, qc/bold_in_mni.png
```
 
### Note
 
FSLeyes GUI stopped opening — a WSL X display problem, not FSL. Four instances
had piled up holding 2.6 GB. `pkill` only caught the wrapper scripts; had to
`kill -9` by PID. Worked around it with `fsleyes render`, which writes a PNG
directly without needing a window.
 

