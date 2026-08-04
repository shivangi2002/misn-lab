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
