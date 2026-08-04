#!/usr/bin/env bash
OUT="env/environment_$(date +%Y-%m-%d).txt"
{
  echo "captured: $(date)"
  uname -a
  grep PRETTY_NAME /etc/os-release
  echo "FSLDIR=$FSLDIR"
  echo "FSL $(cat $FSLDIR/etc/fslversion)"
  fsleyes --version 2>/dev/null
  python --version
  pip freeze
} > "$OUT"
echo "wrote $OUT"
