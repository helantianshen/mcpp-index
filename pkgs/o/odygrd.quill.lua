package = {
    spec        = "1",
    namespace   = "odygrd",
    name        = "quill",
    description = "Asynchronous logging through the upstream quill C++ module",
    licenses    = { "MIT" },
    repo        = "https://github.com/odygrd/quill",
    type        = "package",

    xpm = {
        linux = {
            ["13.0.0"] = {
                url = "https://github.com/odygrd/quill/archive/refs/tags/v13.0.0.tar.gz",
                sha256 = "88b4a1542125577a4d51cf444c51e34d63618c422ba6a4fa9bd23894b49d696b",
            },
        },
        macosx = {
            ["13.0.0"] = {
                url = "https://github.com/odygrd/quill/archive/refs/tags/v13.0.0.tar.gz",
                sha256 = "88b4a1542125577a4d51cf444c51e34d63618c422ba6a4fa9bd23894b49d696b",
            },
        },
        windows = {
            ["13.0.0"] = {
                url = "https://github.com/odygrd/quill/archive/refs/tags/v13.0.0.tar.gz",
                sha256 = "88b4a1542125577a4d51cf444c51e34d63618c422ba6a4fa9bd23894b49d696b",
            },
        },
    },

    mcpp = {
        language     = "c++23",
        import_std   = false,
        modules      = { "quill" },
        include_dirs = { "*/include" },
        sources      = { "*/src/quill.cppm" },
        targets      = { ["quill"] = { kind = "lib" } },
        deps         = {},
        linux = {
            -- 模块与消费者的线程编译配置须一致，线程库在最终链接时引入
            ldflags = { "-pthread" },
        },
    },
}

import("xim.libxpkg.pkginfo")

function install()
    local wrap = "quill-" .. pkginfo.version()
    local source = path.join(wrap, "src/quill.cc")
    local content = assert(io.readfile(source), "odygrd.quill: cannot read " .. source)
    local _, count = content:gsub("export module quill;", "")
    assert(count == 1, "odygrd.quill: expected exactly one module declaration")
    local function patch(before, after)
        local pattern = before:gsub("(%W)", "%%%1")
        local patched, matches = content:gsub(pattern, function() return after end)
        assert(matches == 1, "odygrd.quill: expected exactly one patch match")
        content = patched
    end

    -- Clang 的资源目录在 ARM 上也含 x86 头，存在性检查不能代替目标架构判断
    patch("#if !defined(__INTEL_COMPILER)\r\n",
        "#if !defined(__INTEL_COMPILER) && (defined(__i386__) || defined(__x86_64__) || defined(_M_IX86) || defined(_M_X64))\r\n")
    -- Mach 声明属于系统全局模块，须在 Quill 的模块声明前完成包含
    patch("export module quill;\r\n",
        "#if defined(__APPLE__)\r\n#include <mach/mach_error.h>\r\n#include <mach/thread_act.h>\r\n#include <mach/thread_policy.h>\r\n#endif\r\n\r\nexport module quill;\r\n")
    -- Clang 通过接口扩展名识别模块，原始入口保留在归档树中
    io.writefile(path.join(wrap, "src/quill.cppm"), content)

    local prefix = pkginfo.install_dir()
    os.tryrm(prefix)
    os.mkdir(prefix)
    os.mv(wrap, path.join(prefix, wrap))
    return true
end
