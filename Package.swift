// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Topline",
    platforms: [.macOS(.v13)],
    targets: [
        // 系统自带 libz 的 C 接口桥。KRC 解压必须用标准 zlib：
        // Apple Compression/NSData 的 "zlib" 均为私有变体，解不了酷狗的标准流（实测）
        .systemLibrary(name: "CZlibShim", pkgConfig: nil, providers: []),
        .executableTarget(name: "Topline", dependencies: ["CZlibShim"]),
        .testTarget(name: "ToplineTests", dependencies: ["Topline"]),
    ]
)
