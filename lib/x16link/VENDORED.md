# Vendored: X16Link client library

These files are a copy of `lib/x16link/` from the X16 Office Suite workspace (`~/x16-office/lib/x16link`
on the development machine, not published yet), taken on 2026-11-17 together with this commit. They are
here so the repo builds from a fresh clone. Don't edit them here. Change the workspace copy and
copy it over again (`tools/vendor_x16link.sh`). The wire protocol is described in the workspace's
PROTOCOL.md, and `README.md` in this folder covers the API, key file and memory rules.

Not vendored: the library's tests (`lib/x16link/test/`), which need the sync hub.
