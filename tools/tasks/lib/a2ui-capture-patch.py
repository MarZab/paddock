"""Prepares an A2UI checkout for capture:a2ui (PAD-146.1): adds the Capture executable target and,
on Linux, OpenCombine in place of Combine (A2UICore imports Combine, which Linux does not have).

    python3 -I a2ui-capture-patch.py CHECKOUT linux|mac
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
linux = sys.argv[2] == "linux"
package = root / "Package.swift"
text = package.read_text()

text = text.replace(
    "    // ── Tests ──",
    """    .executableTarget(
      name: "Capture",
      dependencies: ["A2UICore", "BasicCatalog", .product(name: "OrderedJSON", package: "swift-json-schema")],
      path: "capture/Capture"
    ),
    // ── Tests ──""",
    1,
)
if "capture/Capture" not in text:
    sys.exit("Package.swift changed shape: no '// ── Tests ──' marker to add the Capture target before")

if linux:
    text = text.replace(
        "  dependencies: [\n",
        '  dependencies: [\n    .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),\n',
        1,
    )
    text = text.replace(
        '      name: "A2UICore",\n      dependencies: [\n',
        '      name: "A2UICore",\n      dependencies: [\n'
        '        .product(name: "OpenCombine", package: "OpenCombine", condition: .when(platforms: [.linux])),\n',
        1,
    )
    if "OpenCombine" not in text:
        sys.exit("Package.swift changed shape: could not add OpenCombine")
    shim = "#if canImport(Combine)\nimport Combine\n#else\nimport OpenCombine\n#endif\n"
    # On Apple platforms Foundation re-exports Combine, so some files use it without importing it.
    uses = re.compile(r"\b(ObservableObject|AnyCancellable|AnyPublisher|PassthroughSubject|CurrentValueSubject|objectWillChange)\b")
    for source in (root / "swift/core/Sources").rglob("*.swift"):
        body = source.read_text()
        if "import Combine\n" in body:
            body = body.replace("import Combine\n", shim, 1)
        elif uses.search(body):
            body = re.sub(r"^import Foundation\n", "import Foundation\n" + shim, body, count=1, flags=re.M)
        else:
            continue
        source.write_text(body)

package.write_text(text)
