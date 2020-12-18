// swift-tools-version:5.2
import PackageDescription
let packageName = "QsibSensor" // <-- Change this to yours
let package = Package(
  name: "",
  // platforms: [.iOS("9.0")],
  products: [
    .library(name: packageName, targets: [packageName])
  ],
  targets: [
    .target(
      name: packageName,
      path: packageName
    )
  ]
)
