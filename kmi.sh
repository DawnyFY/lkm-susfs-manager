# SPDX-License-Identifier: GPL-2.0-only
# Pick the packaged KMI for a kernel release string. The packaged set lives in
# "$2/kmis" (one <android-os>-<kver> per line), so adding a KMI needs no edit here.
select_kmi() {
  rel="$1"
  while IFS= read -r kmi; do
    [ -n "$kmi" ] || continue
    os="${kmi%-*}"
    kver="${kmi#*-}"
    case "$rel" in
      "$kver".*-"$os"-*) echo "$kmi"; return 0 ;;
    esac
  done < "$2/kmis"
  # A present but non-matching Android tag is a real mismatch, not a tag-less kernel.
  case "$rel" in *android[0-9]*) return 1 ;; esac
  # Tag-less: match by version alone, only when it maps to one packaged KMI (5.10 and
  # 5.15 are shared, so refused), with a numeric patch level.
  match=""
  n=0
  while IFS= read -r kmi; do
    [ -n "$kmi" ] || continue
    kver="${kmi#*-}"
    case "$rel" in "$kver".*) ;; *) continue ;; esac
    patch="${rel#"$kver".}"; patch="${patch%%-*}"
    case "$patch" in ''|*[!0-9]*) continue ;; esac
    match="$kmi"; n=$((n + 1))
  done < "$2/kmis"
  [ "$n" = 1 ] && { echo "$match"; return 0; }
  return 1
}

# 列出所有已打包的 KMI（lib/ 下真实存在的 .ko）
list_kmis() {
    _d=$1
    [ -f "$_d/kmis" ] || return 0
    while IFS= read -r _k; do
        [ -n "$_k" ] || continue
        [ -s "$_d/lib/susfs_guard_lkm-$_k.ko" ] && echo "$_k"
    done < "$_d/kmis"
}

# 当自动匹配失败时，尽力猜一个候选：版本号只对上一档就够了
guess_kmis() {
    _rel=$1
    _d=$2
    for _k in $(list_kmis "$_d"); do
        _kver=${_k#*-}
        case "$_rel" in
            "$_kver".*) echo "$_k" ;;
        esac
    done
}
