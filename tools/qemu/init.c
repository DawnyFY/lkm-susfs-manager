#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sys/reboot.h>
#include <errno.h>

static int write_file(const char *path, const char *s) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) return -1;
    ssize_t n = write(fd, s, strlen(s));
    close(fd);
    return n == (ssize_t)strlen(s) ? 0 : -1;
}

static int load_module(const char *path, const char *params) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) { printf("[init] open %s: %s\n", path, strerror(errno)); return -1; }
    long rc = syscall(SYS_finit_module, fd, params, 0);
    printf("[init] finit_module rc=%ld errno=%d (%s)\n", rc, errno, strerror(errno));
    close(fd);
    return rc == 0 ? 0 : -1;
}

static int dir_has(const char *dir, const char *name) {
    DIR *d = opendir(dir);
    if (!d) return -1;
    struct dirent *e; int found = 0;
    while ((e = readdir(d))) if (!strcmp(e->d_name, name)) { found = 1; break; }
    closedir(d);
    return found;
}

/* 以普通应用 uid 检查可见性（hide_from_apps=1 时 root 不受影响）*/
static void check_as_app(const char *dir, const char *name) {
    pid_t p = fork();
    if (p == 0) {
        setgid(10123); setuid(10123);
        int vis = dir_has(dir, name);
        int st = access(dir[0] ? "/tmp/loopdir/secret" : "", F_OK);
        printf("[app uid=10123] 目录列表可见: %s | access: %s\n",
               vis == 1 ? "是" : vis == 0 ? "否" : "读取失败",
               st == 0 ? "可见" : "ENOENT");
        _exit(0);
    }
    int status; waitpid(p, &status, 0);
}

static void dump_head(const char *what) {
    char buf[2048];
    int fd = open("/proc/susfs_path", O_RDONLY);
    if (fd < 0) { printf("[init] 打开节点失败: %s\n", strerror(errno)); return; }
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) { printf("[init] %s: 空\n", what); return; }
    buf[n] = 0;
    char *line = strtok(buf, "\n");
    int shown = 0;
    printf("[init] %s:\n", what);
    while (line && shown < 6) {
        if (!strncmp(line, "path=", 5) || !strncmp(line, "pend:", 5) || !strncmp(line, "dirent:", 7) || !strncmp(line, "hide_from_apps", 14)) {
            printf("    %s\n", line); shown++;
        }
        line = strtok(NULL, "\n");
    }
}

int main(void) {
    mkdir("/proc", 0755); mkdir("/sys", 0755); mkdir("/dev", 0755); mkdir("/tmp", 0777);
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("tmpfs", "/tmp", "tmpfs", 0, NULL);
    printf("\n[init] ===== QEMU add_loop 语义验证 =====\n");

    if (load_module("/susfs_guard_lkm.ko", "expose_proc=1") != 0) { printf("[init] 模块加载失败\n"); goto done; }
    printf("[init] 模块已加载: %s\n", access("/sys/module/susfs_guard_lkm", F_OK) == 0 ? "是" : "否");

    if (mkdir("/tmp/loopdir", 0777) != 0 && errno != EEXIST) printf("[init] mkdir loopdir: %s\n", strerror(errno));
    chmod("/tmp/loopdir", 0777);
    printf("[init] 目标存在? %s（应为否：测「路径稍后出现」）\n", access("/tmp/loopdir/secret", F_OK) == 0 ? "是" : "否");

    char cmd[256]; snprintf(cmd, sizeof(cmd), "add_loop /tmp/loopdir/secret");
    int rc = write_file("/proc/susfs_path", cmd);
    printf("[init] 写入 \"%s\" -> %s\n", cmd, rc == 0 ? "成功" : strerror(errno));
    dump_head("写入后");

    if (mkdir("/tmp/loopdir/secret", 0777) != 0) printf("[init] mkdir secret 失败: %s\n", strerror(errno));
    else printf("[init] 已创建 /tmp/loopdir/secret\n");
    sleep(4);
    dump_head("创建并等待 4 秒后");

    printf("[init] root 视角: 目录列表可见 %d | access %s\n", dir_has("/tmp/loopdir", "secret"),
           access("/tmp/loopdir/secret", F_OK) == 0 ? "可见" : "ENOENT");
    check_as_app("/tmp/loopdir", "secret");

done:
    printf("[init] ===== 验证结束 =====\n");
    sync(); reboot(0x4321fedc);
    for (;;) pause();
}