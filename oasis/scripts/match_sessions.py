"""
Match each MR session that has a BOLD scan to its nearest clinical visit.

Inputs:
  oasis/data/clinical/mr_sessions.csv                  exported from XNAT
  oasis/data/clinical/.../OASIS3_UDSb4_cdr.csv         CDR + diagnosis per visit
  oasis/data/subject_lists/cn_final.txt, ad_final.txt  the chosen subjects

Output:
  oasis/data/subject_lists/matched_sessions.csv        one row per usable session
"""

import pandas as pd

CDR_PATH = "oasis/data/clinical/OASIS3_data_files/UDSb4/csv/OASIS3_UDSb4_cdr.csv"
MAX_GAP_DAYS = 365          # a diagnosis more than a year from the scan is not
                            # trustworthy - the subject could have converted

# ---- load ----
sessions = pd.read_csv("oasis/data/clinical/mr_sessions.csv")
cdr = pd.read_csv(CDR_PATH)
cn = [l.strip() for l in open("oasis/data/subject_lists/cn_final.txt") if l.strip()]
ad = [l.strip() for l in open("oasis/data/subject_lists/ad_final.txt") if l.strip()]

print(f"sessions in OASIS-3:      {len(sessions)}")
print(f"clinical visits:          {len(cdr)}")
print(f"chosen subjects:          {len(cn)} CN + {len(ad)} AD")

# ---- keep only sessions with a BOLD scan, from my subjects ----
mine = sessions[
    sessions["Scans"].str.contains("bold", na=False)
    & sessions["Subject"].isin(cn + ad)
].copy()

mine["day"] = mine["MR ID"].str.extract(r"_d(\d+)").astype(int)
print(f"sessions with BOLD:       {len(mine)} across {mine['Subject'].nunique()} subjects")

# ---- match each session to its nearest clinical visit ----
rows = []
for _, s in mine.iterrows():
    visits = cdr[cdr["OASISID"] == s["Subject"]].copy()
    if visits.empty:
        continue
    visits["gap"] = (visits["days_to_visit"] - s["day"]).abs()
    best = visits.loc[visits["gap"].idxmin()]
    rows.append({
        "session":   s["MR ID"],
        "subject":   s["Subject"],
        "scanner":   s["Scanner"],
        "mr_day":    s["day"],
        "visit_day": best["days_to_visit"],
        "gap_days":  int(best["gap"]),
        "cdr":       best["CDRTOT"],
        "dx":        best["dx1"],
    })

matched = pd.DataFrame(rows)
print(f"matched to a visit:       {len(matched)}")

# ---- drop matches where the clinical visit is too far from the scan ----
matched = matched[matched["gap_days"] <= MAX_GAP_DAYS]
print(f"within {MAX_GAP_DAYS} days:          {len(matched)}")

# ---- one session per subject: the one closest to a clinical visit ----
matched = matched.sort_values("gap_days").groupby("subject").first().reset_index()

# ---- label from CDR ----
matched["group"] = matched["cdr"].apply(lambda c: "CN" if c == 0 else "AD")
matched = matched[matched["cdr"] != 0.5]          # drop MCI: two-class problem

print()
print(matched[["subject", "session", "scanner", "gap_days", "cdr", "group"]].to_string(index=False))
print()
print(matched["group"].value_counts().to_string())
print(f"gap: mean {matched['gap_days'].mean():.0f} days, max {matched['gap_days'].max()}")
print(matched["scanner"].value_counts().to_string())

matched.to_csv("oasis/data/subject_lists/matched_sessions.csv", index=False)
print("\nwritten to oasis/data/subject_lists/matched_sessions.csv")
