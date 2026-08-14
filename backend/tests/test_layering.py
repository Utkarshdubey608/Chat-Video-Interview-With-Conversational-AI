"""The web surface must stay separable.

`/api/web/*` is a transitional namespace: at some point its routes merge into the
common surface and the duplicates (two-way, Gemini generate, Tavus, Deepgram)
collapse. That consolidation is only a refactor rather than a rewrite while the
boundary holds, and a boundary that is only a convention does not hold.

Three rules, each with a test:

1. Nothing outside `app/web/` imports from it — so the surface stays deletable.
2. `app/web/` never imports `app.routers.*` — the mobile/desktop API. Sharing
   goes through the kernel, never sideways between the two surfaces.
3. `app/web/` only imports kernel modules from `app.*`, never the common
   surface's domain logic — otherwise a change made for the web breaks mobile.
"""

from __future__ import annotations

import ast
from pathlib import Path

APP = Path(__file__).resolve().parent.parent / "app"

# The shared kernel: configuration, auth, Firestore bootstrap, rate limiting and
# the vendor clients. Both surfaces build on these, so a change here is reviewed
# against both. Anything in `app.*` NOT listed is the common surface's own domain
# logic and is off limits to the web package.
#
# The bare package name `app` is deliberately absent: listing it would make the
# prefix test below match every `app.*` module and whitelist the whole codebase.
# `from app import providers` is handled by expanding it to `app.providers` in
# `_imports`, so the submodule is what gets checked.
KERNEL = {
    "app.config",
    "app.security",
    "app.firebase",
    "app.ratelimit",
    "app.providers",
    # Mail transport is shared deliberately, not by accident. `app.mailer` was
    # rewritten as a generic SMTP sender precisely so one implementation serves both
    # surfaces: the web invite flow needs a per-send From, a reply-to and the
    # X-Mailin-custom header, and mobile needs none of them but is unharmed by their
    # existing. A second copy in app/web/ would be two things to keep in sync on the
    # one path where a mistake means a candidate never hears from anyone.
    #
    # The consequence: a change to app/mailer.py is a change to the MOBILE contract
    # too, so it is reviewed against `/api/emails/send` — see tests/test_mailer_modes.py.
    "app.mailer",
}


def _module_name(path: Path) -> str:
    """`app/web/store/db.py` -> `app.web.store.db`."""
    rel = path.relative_to(APP.parent).with_suffix("")
    parts = [p for p in rel.parts if p != "__init__"]
    return ".".join(parts)


def _imports(path: Path) -> set[str]:
    """Absolute module names imported by a file.

    Two details make this accurate enough to be worth trusting:

    * Relative imports are resolved against the file's own package, so
      `from .db import WebStore` inside `app/web/store/` is seen as
      `app.web.store.db` rather than skipped.
    * `from <pkg> import a, b` also yields `<pkg>.a` and `<pkg>.b`. Without that,
      `from app import interviews` would be recorded only as `app` and every rule
      below would miss it — the imported name IS the module in that form.
    """
    tree = ast.parse(path.read_text(encoding="utf-8"))
    own = _module_name(path)
    package = own.rsplit(".", 1)[0] if "." in own else own

    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.level == 0:
                base = node.module or ""
            elif node.level == 1:
                base = f"{package}.{node.module}" if node.module else package
            else:
                trimmed = package.rsplit(".", node.level - 1)[0]
                base = f"{trimmed}.{node.module}" if node.module else trimmed
            if not base:
                continue
            names.add(base)
            # `from app import providers` -> also record `app.providers`.
            names.update(f"{base}.{alias.name}" for alias in node.names)
    return names


def _python_files(*, inside_web: bool) -> list[Path]:
    return [
        path
        for path in sorted(APP.rglob("*.py"))
        if ("web" in path.relative_to(APP).parts) is inside_web
    ]


def _is_kernel(name: str) -> bool:
    return name in KERNEL or any(name.startswith(f"{k}.") for k in KERNEL)


# `app/main.py` is the ONE designated consumer: it calls `web.install(app)`. That
# single call is the mount point the whole design rests on, and
# `test_main_installs_the_web_surface_exactly_once` pins it to exactly one. Every
# other module importing the web surface is a leak.
MOUNT_POINT = "main.py"


def test_nothing_outside_the_web_package_imports_it() -> None:
    """Rule 1 — the web surface has one consumer, so it can be removed."""
    offenders = [
        f"{path.relative_to(APP)} imports {name}"
        for path in _python_files(inside_web=False)
        if path.name != MOUNT_POINT
        for name in _imports(path)
        if name == "app.web" or name.startswith("app.web.")
    ]
    assert not offenders, (
        "the web surface has leaked into the common surface and is no longer "
        "removable:\n  " + "\n  ".join(offenders)
    )


def test_the_web_package_never_imports_the_common_routers() -> None:
    """Rule 2 — no sideways coupling between the two API surfaces."""
    offenders = [
        f"{path.relative_to(APP)} imports {name}"
        for path in _python_files(inside_web=True)
        for name in _imports(path)
        if name == "app.routers" or name.startswith("app.routers.")
    ]
    assert not offenders, (
        "the web surface reaches into the mobile/desktop API; share through the "
        "kernel instead:\n  " + "\n  ".join(offenders)
    )


def test_the_web_package_only_imports_kernel_modules() -> None:
    """Rule 3 — the web surface builds on the kernel, not on mobile's domain logic."""
    offenders = [
        f"{path.relative_to(APP)} imports {name}"
        for path in _python_files(inside_web=True)
        for name in _imports(path)
        # `app` alone carries no information — `_imports` expands the names it
        # brought in, and those are what get judged.
        if name != "app"
        and name.startswith("app")
        and not name.startswith("app.web")
        and not _is_kernel(name)
    ]
    assert not offenders, (
        "the web surface imports common-surface domain logic. Either it belongs "
        "in the kernel (add it to KERNEL here, and review the change against the "
        "mobile API) or the web surface needs its own copy:\n  "
        + "\n  ".join(offenders)
    )


def test_main_installs_the_web_surface_exactly_once() -> None:
    """The single mount point — two edits to remove the surface, not a hunt."""
    source = (APP / "main.py").read_text(encoding="utf-8")
    assert source.count("web.install(app)") == 1
