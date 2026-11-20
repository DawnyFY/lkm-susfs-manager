# SPDX-License-Identifier: GPL-2.0-only
# Pick the packaged KMI for a kernel release string. The packaged set lives in
# "$2/kmis" (one <android-os>-<kver> per line), so adding a KMI needs no edit here.

# Android 用户态 SDK -> 打包的 androidNN 前缀。仅用于无 Android tag 的共享内核
# 分支（5.10/5.15）：同一个内核 minor 对应 android13/android14 等多个 KMI 时，
# 用系统 SDK 消歧，避免直接拒绝加载。取不到 SDK 时返回失败，保持保守拒绝。
sdk_android_os() {
    _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
    case "$_sdk" in
        31|32) echo android12 ;;
        33) echo android13 ;;
        34) echo android14 ;;
        35) echo android15 ;;
        36) echo android16 ;;
        37) echo android17 ;;
        *) return 1 ;;
    esac
}
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
  # 有 android 标签但不配对：先按内核版本兜底（唯一命中才用），避免 Android 版本号
  # 跟平台走而内核 ABI 仍是旧分支时整机静默不加载。
  case "$rel" in
    *android[0-9]*)
      _fb=""
      _fn=0
      while IFS= read -r _kmi; do
        [ -n "$_kmi" ] || continue
        _kver="${_kmi#*-}"
        case "$rel" in "$_kver".*) ;; *) continue ;; esac
        _p="${rel#"$_kver".}"; _p="${_p%%-*}"
        case "$_p" in ''|*[!0-9]*) continue ;; esac
        _fb="$_kmi"; _fn=$((_fn + 1))
      done < "$2/kmis"
      [ "$_fn" = 1 ] && { echo "$_fb"; return 0; }
      return 1
      ;;
  esac
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
  # 共享内核 minor（5.10/5.15）且无 Android tag：用用户态 SDK 精确消歧
  _os=$(sdk_android_os) || return 1
  while IFS= read -r _kmi; do
    [ -n "$_kmi" ] || continue
    _kver="${_kmi#*-}"
    case "$rel" in "$_kver".*) ;; *) continue ;; esac
    _p="${rel#"$_kver".}"; _p="${_p%%-*}"
    case "$_p" in ''|*[!0-9]*) continue ;; esac
    [ "$_kmi" = "$_os-$_kver" ] || continue
    [ -s "$2/lib/susfs_guard_lkm-$_kmi.ko" ] || continue
    echo "$_kmi"; return 0
  done < "$2/kmis"
  # SDK 对不上（例如 Android 16 跑 5.15 内核，包里没有 android16-5.15）：
  # 这里只给出「建议值」，不自动采用 —— bin/susfs_insmod 会改写 vermagic 后重试加载，
  # 选错有可能真的把不同 android tag 的 ko 装进内核（审计实测字符串证据），
  # 所以宁可让用户显式指定。
  return 1
}

# 当自动匹配失败时，猜一个最可能的候选并打印出来（仅供提示，不做加载决策）
suggest_kmi() {
  rel="$1"
  _sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  case "$_sdk" in ''|*[!0-9]*) _sdk=0 ;; esac
  _best=""
  _best_api=0
  while IFS= read -r _kmi; do
    [ -n "$_kmi" ] || continue
    _kver="${_kmi#*-}"
    case "$rel" in "$_kver".*) ;; *) continue ;; esac
    _p="${rel#"$_kver".}"; _p="${_p%%-*}"
    case "$_p" in ''|*[!0-9]*) continue ;; esac
    [ -s "$2/lib/susfs_guard_lkm-$_kmi.ko" ] || continue
    case "${_kmi%-*}" in
      android12) _api=31 ;;
      android13) _api=33 ;;
      android14) _api=34 ;;
      android15) _api=35 ;;
      android16) _api=36 ;;
      android17) _api=37 ;;
      *) continue ;;
    esac
    [ "$_api" -le "$_sdk" ] || continue
    if [ "$_api" -gt "$_best_api" ]; then _best=$_kmi; _best_api=$_api; fi
  done < "$2/kmis"
  [ -n "$_best" ] || return 1
  echo "$_best"; return 0
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