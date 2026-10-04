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
    -- Clang 通过接口扩展名识别模块，副本保留上游内容和换行
    os.cp(source, path.join(wrap, "src/quill.cppm"))

    local prefix = pkginfo.install_dir()
    os.tryrm(prefix)
    os.mkdir(prefix)
    os.mv(wrap, path.join(prefix, wrap))
    return true
end
