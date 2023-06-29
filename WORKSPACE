workspace(name = "asm")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# See https://github.com/google/bazel-common for how to update these values
http_archive(
  name = "google_bazel_common",
  sha256 = "b54410b99dd34e17dc02fc6186d478828b0d34be3876769dba338c6ccec2cea9",
  strip_prefix = "bazel-common-221ecf2922e8ebdf8e002130e9772045cfa2f464",
  urls = ["https://github.com/google/bazel-common/archive/221ecf2922e8ebdf8e002130e9772045cfa2f464.zip"],
)


load("@google_bazel_common//:workspace_defs.bzl", "google_common_workspace_rules")

google_common_workspace_rules()
