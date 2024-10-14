load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "HlsFFmpeg",
    module_name = "HlsFFmpeg",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    deps = [
      "//submodules/AdUI",
    ],
    visibility = [
        "//visibility:public",
    ],
)
