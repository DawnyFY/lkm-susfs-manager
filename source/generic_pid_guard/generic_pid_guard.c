// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/sched.h>
#include <linux/cred.h>
#include <linux/string.h>
#include <linux/version.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 10, 0)
#error "requires Linux 5.10+"
#endif
#if !defined(CONFIG_ARM64)
#error "arm64 only"
#endif

#define MAX_UID_RANGES 16
#define MAX_COMMS 16
#define COMM_LEN 32

struct uid_range { u32 lo, hi; };
static struct uid_range uid_ranges[MAX_UID_RANGES];
static int n_uid_ranges;
static char comms[MAX_COMMS][COMM_LEN];
static int n_comms;
static char excludes[MAX_COMMS][COMM_LEN];
static int n_excludes;

static char param_uids[256] = "99000-99999";
/* 0440：参数只在 insmod 时设定。目标 UID/comm 清单属于检测面信息，
 * 不能让普通进程从 sysfs 的 parameters 目录读到。 */
module_param_string(target_uids, param_uids, sizeof(param_uids), 0440);
MODULE_PARM_DESC(target_uids, "comma-separated UIDs/ranges, e.g. 99000-99999,10516");

static char param_comms[512] = "probe-leaf*,canProbe*,ivecheck*";
module_param_string(target_comms, param_comms, sizeof(param_comms), 0440);
MODULE_PARM_DESC(target_comms, "comma-separated comm prefixes with optional *");

static char param_excludes[256] = "nqiunativecheck";
module_param_string(exclude_comms, param_excludes, sizeof(param_excludes), 0440);
MODULE_PARM_DESC(exclude_comms, "comma-separated comm prefixes never matched");

static int parse_list(const char *s, char out[][COMM_LEN], int max)
{
    int n = 0;
    while (*s && n < max) {
        const char *comma = strchr(s, ',');
        size_t len = comma ? (size_t)(comma - s) : strlen(s);
        while (len && (*s == ' ' || *s == '\t')) { s++; len--; }
        while (len && (s[len-1] == ' ' || s[len-1] == '\t')) len--;
        if (len >= COMM_LEN) len = COMM_LEN - 1;
        if (len) { memcpy(out[n], s, len); out[n][len] = 0; n++; }
        if (!comma) break;
        s = comma + 1;
    }
    return n;
}

static int parse_uids(const char *s)
{
    int n = 0;
    while (*s && n < MAX_UID_RANGES) {
        char *end;
        unsigned long lo = simple_strtoul(s, &end, 10);
        unsigned long hi = lo;
        if (*end == '-') { s = end + 1; hi = simple_strtoul(s, &end, 10); }
        if (end == s) break;
        if (hi >= lo) { uid_ranges[n].lo = (u32)lo; uid_ranges[n].hi = (u32)hi; n++; }
        if (*end == ',') s = end + 1; else break;
    }
    return n;
}

static bool comm_prefix(const char *comm, const char *pat)
{
    size_t n = strlen(pat);
    if (n && pat[n-1] == '*') n--;
    /* 空前缀（例如裸 "*"）会匹配所有进程 —— 那等于全系统伪装 getppid，
     * 所以这里直接判定为不匹配，配置侧也会拒绝这种写法。 */
    if (n == 0) return false;
    return !strncmp(comm, pat, n);
}

static bool is_target(void)
{
    int i;
    u32 uid = current_uid().val;
    for (i = 0; i < n_excludes; i++)
        if (comm_prefix(current->comm, excludes[i])) return false;
    for (i = 0; i < n_uid_ranges; i++)
        if (uid >= uid_ranges[i].lo && uid <= uid_ranges[i].hi) return true;
    for (i = 0; i < n_comms; i++)
        if (comm_prefix(current->comm, comms[i])) return true;
    return false;
}

static int gp_ret(struct kretprobe_instance *ri, struct pt_regs *regs)
{
    if (is_target())
        regs->regs[0] = 1;
    return 0;
}

static struct kretprobe gp_kr = {
    .kp.symbol_name = "__arm64_sys_getppid",
    .handler = gp_ret,
    .maxactive = 64,
};

static int __init gp_init(void)
{
    int rc;
    n_uid_ranges = parse_uids(param_uids);
    n_comms = parse_list(param_comms, comms, MAX_COMMS);
    n_excludes = parse_list(param_excludes, excludes, MAX_COMMS);
    pr_info("generic_pid_guard: ranges=%d comms=%d excludes=%d\n", n_uid_ranges, n_comms, n_excludes);
    rc = register_kretprobe(&gp_kr);
    if (rc) pr_err("generic_pid_guard: register failed %d\n", rc);
    return rc;
}
static void __exit gp_exit(void){unregister_kretprobe(&gp_kr);}
module_init(gp_init); module_exit(gp_exit);
MODULE_LICENSE("GPL");
